#!/usr/bin/env python3
"""folio SRS render-gate (taxonomy §5.2 gate F) — 生成 SRS プレゼン HTML の決定的 render 健全性検査。

verify-srs.sh (gate A-E,G,H + visual-first) は pure-bash で render 後の DOM を見れないため、 本 gate が
headless chromium で実 render し、 probe-srs.js で 4 class を検出する:
  (1) horizontal-overflow — 意図しない document 横スクロール
  (2) component-overlap   — data-component block 同士の矩形交差
  (2b) clipped-content    — overflow-x:hidden/clip 要素が中身を横に切り落とし scroll 不能 (mobile-clip 盲点・folio-276 #2)
  (3) low-contrast        — text↔実効背景の WCAG AA 未満 (S3 で手検出した dark-contrast 崩壊型)
検査は **light / dark 両 color-scheme × 3 viewport (375/768/1280)** の直積で行う。 dark 専用の崩れ
(色トークンの dark override 漏れ等) は dark を実際に emulate しないと捕れない (S3 の実欠陥がこの class)。

既存 folio render-gate (tests/render-gate/check.py、 mermaid flowchart 専用・corpus sweep) とは別系統。
本 gate は単一 SRS HTML を対象にし、 生成 SRS 固有の color/overflow/overlap を見る。 幾何定数 (横溢れ許容・
overlap 面積比) は probe.js (ADR-0037) の値を probe-srs.js が複製する (drift は test-adversarial A35 が検知)。

被覆限界 (honest disclosure): taxonomy §5.2 gate F は「overlap / 横幅超過 / 不可視化」を掲げる。 「不可視化」の
うち (a) low-contrast (読めない=実質不可視)、 (b) overflow-x:hidden/clip による *横方向* の content clip
(clipped-content arm・folio-276 #2) を捕捉する。 残る未対応: 縦方向 clip / visibility:hidden / overflow:hidden に
よる *完全* invisibility (mermaid probe.js の content-clipped 相当) — 必須部品が CSS バグで丸ごと不可視化しても
violation でなく検査対象外になる (visible() を除外 filter として使うため)。 これは ADR-0037 が
best-effort tier とし folio-w5z 系列へ漸進としたのと同じ posture。 gradient/image 背景のうち色不明な image
(url()) も同様に skip され、 件数を gradient skip として disclose する (停止色のある gradient は worst-case 評価)。

決定性: 生成 SRS は CSS inline 同梱で自己完結。 playwright 版 pin (requirements.txt) + CI font pin
(fonts-noto-cjk) で layout/text-shaping を固定する。 host (pip 不在) では uv 経由で実行する:
  ~/.local/bin/uv run --with playwright==1.60.0 python render-gate-srs.py <html>

fail-closed: text が 1 つも評価できない (render 破綻) は「clean」でなく FAIL に倒す。 違反 1 件でも exit 1。

usage:
  render-gate-srs.py <generated.html>          # 単一 SRS を light/dark × 3 viewport で検査
  render-gate-srs.py --selftest                # detector の検出力を fixture で自己検証
  render-gate-srs.py --base-url http://...      # 外部 server (html の親 dir 配信必須)
exit: 0 = clean / 1 = 違反 or render 破綻 / 2 = tool error
"""
from __future__ import annotations

import argparse
import contextlib
import functools
import http.server
import json
import socketserver
import sys
import threading
from pathlib import Path

try:
    from playwright.sync_api import sync_playwright
except Exception as e:  # playwright 不在は tool error (gate skip は caller=verify-srs が判断)
    print(f"render-gate-srs: playwright 不在 ({e})", file=sys.stderr)
    sys.exit(2)

SCRIPT_DIR = Path(__file__).resolve().parent
PROBE_JS = (SCRIPT_DIR / "probe-srs.js").read_text(encoding="utf-8")
VIEWPORTS = [(375, 667), (768, 1024), (1280, 900)]
SCHEMES = ["light", "dark"]

# census (gate F sibling) の pseudo-content inverse-allowlist は probe-srs.js __folioSrsRenderCensus 側で
# inverse-allowlist として実装する (独立 ceiling wxnjdmjk9 強化)。 固定 selector 集合は corpus-disjoint
# allowlist で不完全だったため廃し、 probe が body 全要素を走査して genuine chrome allowlist (3 値) の補集合を
# 捏造とみなす。 ゆえに python 側で対象 selector を列挙する必要はない (counts のみ probe へ注入する)。


@contextlib.contextmanager
def serve(root: Path):
    class QuietHandler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *_a):
            pass

    httpd = socketserver.TCPServer(("127.0.0.1", 0), functools.partial(QuietHandler, directory=str(root)))
    t = threading.Thread(target=httpd.serve_forever, daemon=True)
    t.start()
    try:
        yield f"http://127.0.0.1:{httpd.server_address[1]}"
    finally:
        httpd.shutdown()
        httpd.server_close()


def probe(page, url: str, scheme: str) -> dict:
    page.goto(url, wait_until="load")
    page.wait_for_timeout(150)  # web font / layout settle
    page.evaluate(PROBE_JS)
    return page.evaluate("(s) => window.__folioSrsRenderProbe(s)", scheme)


def fmt(result: dict, where: str) -> list[str]:
    lines = []
    for v in result["violations"]:
        detail = ", ".join(f"{k}={v[k]}" for k in v if k not in ("kind", "text"))
        lines.append(f"  [render-gate-srs] {v['kind']}: {where} — {v['text']} ({detail})")
    return lines


def run(base_url: str, target: str, screenshot_dir: Path | None) -> int:
    failures: list[str] = []
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        for scheme in SCHEMES:
            for width, height in VIEWPORTS:
                page = browser.new_page(viewport={"width": width, "height": height}, color_scheme=scheme)
                result = probe(page, f"{base_url}/{target}", scheme)
                where = f"{target}@{width}px/{scheme}"
                n = len(result["violations"])
                tc = result["textChecked"]
                gs = result["gradientSkipped"]
                # fail-closed: text を 1 つも評価できなければ render 破綻 (clean と取り違えない)
                broken = tc == 0
                status = "FAIL" if (n or broken) else "OK"
                note = " — render 破綻 (text 0)" if broken else ""
                gnote = f" / gradient skip {gs}" if gs else ""
                print(f"  [{status}] {where} — {n} 違反 / text {tc} 検査{gnote}{note}")
                if broken:
                    failures.append(f"  [render-gate-srs] broken-render: {where} (contrast 評価対象 text が 0 — render 不全)")
                failures += fmt(result, where)
                if screenshot_dir is not None:
                    d = screenshot_dir / f"{scheme}-{width}px"
                    d.mkdir(parents=True, exist_ok=True)
                    page.screenshot(path=str(d / (target.replace("/", "__") + ".jpg")), full_page=True, type="jpeg", quality=80)
                page.close()
        browser.close()
    print()
    if failures:
        print(f"render-gate-srs: {len(failures)} 件の問題 (overflow / overlap / low-contrast / render 破綻)\n")
        print("\n".join(failures))
        return 1
    print("render-gate-srs: clean — 0 overflow / 0 overlap / 0 low-contrast (light+dark × 3 viewport render 確認済)")
    return 0


def run_selftest(base_url: str) -> int:
    """detector の検出力を fixture で自己検証 (kind 完全一致・fail-closed・viewport/scheme plumbing)。

    各 case = (fixture, viewport幅, scheme, 期待 violation kind 集合)。 kind は **完全一致** (subset 不可)
    — 期待した detector「だけ」が発火することを要求し、 positive fixture 上の他 detector 誤発火を masking
    しない。 同一 fixture を light/dark や 375/1280 で走らせる対が scheme/viewport plumbing の回帰ガード
    (片方が clean・片方が FAIL することで「emulation/幅が実際に効いている」を証明する)。 全 case で
    textChecked>0 も assert する (render 破綻を「clean」と取り違える tautology を塞ぐ)。
    """
    cases = [
        ("srs-clean.html", 375, "light", set()),
        ("srs-clean.html", 375, "dark", set()),
        ("srs-clean.html", 768, "light", set()),    # 768 (tablet) 行も exercise し viewport plumbing を全 3 点で固定
        ("srs-clean.html", 1280, "light", set()),
        ("srs-clean.html", 1280, "dark", set()),
        ("srs-low-contrast-light.html", 1280, "light", {"low-contrast"}),
        # dark 専用崩れ: light で clean・dark で発火 = dark emulation + contrast arm の同時証明 (S3 型)
        ("srs-low-contrast-dark.html", 1280, "light", set()),
        ("srs-low-contrast-dark.html", 1280, "dark", {"low-contrast"}),
        # gradient 上の白文字: 薄い勾配で発火 (ceiling 実証の攻撃クラス)・暗い勾配で clean (多レイヤー合成の
        # 回帰ガード)。 gradient skip でなく停止色 worst-case 評価していることを固定する。
        ("srs-gradient-low-contrast.html", 1280, "light", {"low-contrast"}),
        ("srs-gradient-clean.html", 1280, "light", set()),
        # gradient×dark の交差: light=clean・dark で停止色が明色化し白文字が崩れる = gradient 経路の
        # dark emulation plumbing を pin (solid 専用 srs-low-contrast-dark と同型の証明を gradient でも成立)。
        ("srs-gradient-dark.html", 1280, "light", set()),
        ("srs-gradient-dark.html", 1280, "dark", {"low-contrast"}),
        # url() image 背景の skip 経路: 停止色抽出不能ゆえ contrast 評価せず件数 disclose (best-effort tier)。
        # 通常 text が 1 つあり textChecked>0 (broken-render と取り違えない)・image 上 text は gradientSkipped>0。
        # 5 要素目 = 期待 gradientSkipped>0 (skip 契約が live であることを assert)。
        ("srs-url-image.html", 1280, "light", set(), True),
        # 横溢れ: 375 で発火・1280 で clean = viewport plumbing の証明
        ("srs-h-overflow.html", 375, "light", {"horizontal-overflow"}),
        ("srs-h-overflow.html", 1280, "light", set()),
        # mobile-clip: overflow:hidden wrap 内 min-width table の列潰れ。 375 で clipped-content 発火・
        # 1280 で table が収まり clean = viewport plumbing の証明 + 横 clip が document overflow と別物で
        # ある (= horizontal-overflow でなく clipped-content で鳴る) ことを kind 完全一致で固定する。
        # dark でも同じ幾何で発火させ、 新 arm が gate の light/dark 直積方針と非対称でない (color に依らず
        # clip を捕捉する) ことを pin する。
        ("srs-clipped.html", 375, "light", {"clipped-content"}),
        ("srs-clipped.html", 375, "dark", {"clipped-content"}),
        ("srs-clipped.html", 1280, "light", set()),
        # overlap: 両 data-component (srs-overlap) と 非 data-component 装飾の被さり (noncomp-overlap) の双方を捕捉
        ("srs-overlap.html", 1280, "light", {"component-overlap"}),
        ("srs-noncomp-overlap.html", 1280, "light", {"component-overlap"}),
    ]
    ok = True
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        pages: dict[tuple, object] = {}
        for case in cases:
            name, width, scheme, expect = case[:4]
            expect_skip = case[4] if len(case) > 4 else None  # True なら gradientSkipped>0 を要求
            key = (width, scheme)
            if key not in pages:
                height = next((h for w, h in VIEWPORTS if w == width), 900)
                pages[key] = browser.new_page(viewport={"width": width, "height": height}, color_scheme=scheme)
            page = pages[key]
            result = probe(page, f"{base_url}/render-fixtures/{name}", scheme)
            kinds = {v["kind"] for v in result["violations"]}
            rendered = result["textChecked"] > 0
            skip_ok = expect_skip is None or (result["gradientSkipped"] > 0) == expect_skip
            passed = rendered and kinds == expect and skip_ok
            ok = ok and passed
            verdict = "PASS" if passed else "FAIL"
            exp = ("+".join(sorted(expect)) or "clean") + (f"+skip>0" if expect_skip else "")
            got = ("+".join(sorted(kinds)) or "clean") if rendered else f"render 破綻 (text {result['textChecked']})"
            if expect_skip is not None:
                got += f" (gradientSkipped={result['gradientSkipped']})"
            print(f"  [selftest {verdict}] {name}@{width}px/{scheme}: 期待={exp} / 実際={got}")
        browser.close()
    print()
    if ok:
        print("selftest: PASS — 全 detector arm (overflow / overlap / low-contrast) が kind 完全一致で発火し、 "
              "clean を誤検出せず、 dark emulation・viewport plumbing・fail-closed (textChecked>0) が固定されている")
        return 0
    print("selftest: FAIL — detector が期待通り動作しない (playwright/chromium 版 drift?)")
    return 1


# =============================================================================
# census gate (gate F sibling・folio-6jb 縦軸 = 描画後 content-fidelity)
# =============================================================================
def parse_expect(s: str) -> dict[str, int]:
    """'comp=N,comp=N' を {comp:N} へ。 caller (verify-srs.sh) が contract から導出した期待件数。"""
    counts: dict[str, int] = {}
    for part in (s or "").split(","):
        part = part.strip()
        if not part:
            continue
        if "=" not in part:
            raise ValueError(f"--expect 形式不正 (comp=N 期待): {part!r}")
        k, v = part.split("=", 1)
        counts[k.strip()] = int(v.strip())
    return counts


def census(page, url: str, expect_json: str) -> dict:
    page.goto(url, wait_until="load")
    page.wait_for_timeout(150)  # web font / layout settle (gate F と同値)
    page.evaluate(PROBE_JS)
    return page.evaluate("(j) => window.__folioSrsRenderCensus(j)", expect_json)


def fmt_census(result: dict, where: str) -> list[str]:
    lines = []
    for v in result["violations"]:
        lines.append(f"  [census] {v['kind']}: {where} — {v['text']}")
    return lines


def run_census(base_url: str, target: str, counts: dict[str, int], screenshot_dir: Path | None,
               vocab: dict | None = None) -> int:
    """描画後 content-fidelity census を light/dark × 3 viewport で検査する (gate F と同 matrix)。

    pseudo-content-fabrication (2b8) は scheme 依存 / census-omission (459) は viewport・scheme 条件下の
    隠蔽もあるため、 visual gate と同じ直積で走らせる。 T7 fail-closed: 期待 >0 なのに *全 viewport で*
    可視 0 = render 破綻と判定し、 census-omission とは別の broken-render として FAIL に倒す
    (renderer 設定ミスを「omission 0=clean」と取り違えない)。
    """
    # 'plain' は data-component でなく sub-slot (.plain) 期待件数ゆえ counts から分離し plainCount で注入
    # (DOM 自己参照を廃した contract-anchor。 census 側 expect.plainCount が受領)。
    counts = dict(counts)
    plain_count = counts.pop("plain", None)
    payload: dict = {"counts": counts}
    if plain_count is not None:
        payload["plainCount"] = plain_count
    # census closure 語彙 SSoT (folio-hef.3): verify-srs.sh が srs.census-vocab.yaml から導出した語彙を
    # probe payload (expect.vocab) へ carry する。 S4 (folio-hef.4) の closure 判定 (描画要素 ↔ 期待要素の
    # 全単射) が消費する基盤。 本 slice では probe は受領のみ (bijection 本体は S4)。
    if vocab is not None:
        payload["vocab"] = vocab
    expect_json = json.dumps(payload, ensure_ascii=False)
    failures: list[str] = []
    total_expected = sum(counts.values())
    any_visible = False
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        for scheme in SCHEMES:
            for width, height in VIEWPORTS:
                page = browser.new_page(viewport={"width": width, "height": height}, color_scheme=scheme)
                result = census(page, f"{base_url}/{target}", expect_json)
                where = f"{target}@{width}px/{scheme}"
                n = len(result["violations"])
                tv = result["totalVisible"]
                if tv > 0:
                    any_visible = True
                status = "FAIL" if n else "OK"
                print(f"  [{status}] {where} — 可視 {tv}/{result['totalExpected']} 件 / {n} 違反")
                failures += fmt_census(result, where)
                if screenshot_dir is not None:
                    d = screenshot_dir / f"census-{scheme}-{width}px"
                    d.mkdir(parents=True, exist_ok=True)
                    page.screenshot(path=str(d / (target.replace("/", "__") + ".jpg")), full_page=True, type="jpeg", quality=80)
                page.close()
        browser.close()
    # T7 fail-closed: 期待要素が *どの viewport/scheme でも* 1 件も描画されない = render 破綻。
    if total_expected > 0 and not any_visible:
        failures.append("  [census] broken-render: 期待要素が全 viewport/scheme で可視 0 — render 破綻 (genuine omission と区別し FAIL)")
    print()
    if failures:
        print(f"render census: {len(failures)} 件の問題 (pseudo-content 捏造 / 描画後 omission / render 破綻)\n")
        print("\n".join(failures))
        return 1
    print(f"render census: clean — pseudo-content 捏造 0 / 描画後 omission 0 (期待 {total_expected} 件が light+dark × 3 viewport で全可視)")
    return 0


def run_census_selftest(base_url: str) -> int:
    """census detector の検出力を fixture で自己検証 (kind 完全一致・fail-closed・viewport/scheme plumbing)。

    要件行 2 + NFR 行 1 を基準形状とし、 期待件数を {ears-requirement-row:2, nfr-metric-row:1} で与える。
    各 case = (fixture, 幅, scheme, 期待 kind 集合)。 同一 fixture を 375/1280 や light/dark で走らせる対が
    census の viewport/scheme 直積が実際に効いていることを証明する (条件付き隠蔽・条件付き捏造を捕捉)。
    """
    base = {"ears-requirement-row": 2, "nfr-metric-row": 1}
    # .plain を持つ fixture は plainCount を contract-anchor として与える (DOM 自己参照を廃した検査経路)。
    plainb = {"ears-requirement-row": 2, "nfr-metric-row": 1, "plain": 2}
    # 各 case = (fixture, 幅, scheme, 期待 kind 集合, counts)。 counts は per-case (plainCount 注入のため)。
    cases = [
        ("srs-census-clean.html", 1280, "light", set(), base),
        ("srs-census-clean.html", 375, "dark", set(), base),
        # 2b8 pseudo-content 捏造: light/dark どちらでも .fid::after が発火
        ("srs-census-pseudo.html", 1280, "light", {"pseudo-content-fabrication"}, base),
        ("srs-census-pseudo.html", 375, "dark", {"pseudo-content-fabrication"}, base),
        # 459 comment omission: 静的 2 件・可視 1 件 = census-omission
        ("srs-census-omission.html", 1280, "light", {"census-omission"}, base),
        # 条件付き omission: 375 で display:none 発火・1280 で clean = viewport plumbing 証明
        ("srs-census-responsive.html", 375, "light", {"census-omission"}, base),
        ("srs-census-responsive.html", 1280, "light", set(), base),
        # 条件付き 2b8: dark でのみ ::before 注入・light で clean = scheme plumbing 証明
        ("srs-census-dark-pseudo.html", 1280, "light", set(), base),
        ("srs-census-dark-pseudo.html", 1280, "dark", {"pseudo-content-fabrication"}, base),
        # 2b8 inverse-allowlist: 旧 7 集合外の class (.resp) への ::after 注入 = allowlist 補集合 → 捏造
        ("srs-census-pseudo-other.html", 1280, "light", {"pseudo-content-fabrication"}, base),
        # 459 rendered() clip-path: clip-path:inset(100%) で 1 行を読者非到達 (checkVisibility は true)
        ("srs-census-clip.html", 1280, "light", {"census-omission"}, base),
        # 459 rendered() areaOf: transform:scale(0) で 1 行を描画域 0 に潰す (checkVisibility は true)
        ("srs-census-transform.html", 1280, "light", {"census-omission"}, base),
        # 459 .plain sub-slot: 行は可視のまま行内の平易説明 .plain だけ display:none = row count 素通り omission
        ("srs-census-plainhide.html", 1280, "light", {"census-omission"}, plainb),
        # --- ws4o6ywe5 hardening の新機構 selftest ---
        # A1 ::marker 捏造: display:list-item の ::marker content (旧版は ::before/::after のみ走査)
        ("srs-census-marker.html", 1280, "light", {"pseudo-content-fabrication"}, base),
        # A2 body::before 捏造: 'body *' が body 自身を含まない射程漏れ
        ("srs-census-body-before.html", 1280, "light", {"pseudo-content-fabrication"}, base),
        # B2 near-zero opacity: opacity:0.004 (checkOpacity は ===0 のみ false ゆえ素通りした)
        ("srs-census-opacity.html", 1280, "light", {"census-omission"}, base),
        # B3 overflow 祖先クリップ: max-height:0;overflow:hidden 祖先が子を全クリップ (clipHidden 非検査)
        ("srs-census-overflow.html", 1280, "light", {"census-omission"}, base),
        # B3 自己 content クリップ: height:5px;overflow:hidden で content を縦切り捨て (area>16 弱閾値)
        ("srs-census-tinyheight.html", 1280, "light", {"census-omission"}, base),
        # B1 .plain へ rendered() 適用: .plain{clip-path:inset(100%)} (旧版は .plain を checkVis 単独判定)
        ("srs-census-plainclip.html", 1280, "light", {"census-omission"}, plainb),
        # B4 .plain contract-anchor: .plain 全削除で DOM 0 件 (旧版は plains.length=0 で検査 skip)
        ("srs-census-plaindel.html", 1280, "light", {"census-omission"}, plainb),
        # B5 .plain 非空 rendered text: .plain が zero-width のみ (checkVis=true だが prose 無)
        ("srs-census-plainempty.html", 1280, "light", {"census-omission"}, plainb),
        # B6 distinct req-id: 同 id 行コピーで件数水増し (count-equality は id を問わない)
        ("srs-census-duprow.html", 1280, "light", {"census-omission"}, base),
        # --- folio-hef S1 クラスタ1 述語の新機構 selftest ---
        # FF1 own-element content: 要素自身に content:url(svg) で replaced-element 捏造 (pseudo 走査の射程外)
        ("srs-census-owncontent.html", 1280, "light", {"own-content-fabrication"}, base),
        # FF2 contain:paint clip: contain:paint+height:0 祖先が paint を 0px box に潰す (rendered() 5 述語の射程外)
        ("srs-census-contain.html", 1280, "light", {"census-omission"}, base),
        # --- folio-hef S1 ceiling wf_b544a704 が捕捉した hole の回帰 selftest ---
        # FF1 time-axis: content を animation-delay>150ms で normal→url にフリップ (probe 前 getAnimations().finish() で封鎖)
        ("srs-census-anim.html", 1280, "light", {"own-content-fabrication"}, base),
        # FF2 self-contain: counted 行自身に contain:paint + 子を position で box 外へ押出し (visibleTextArea で捕捉)
        ("srs-census-selfcontain.html", 1280, "light", {"census-omission"}, base),
        # FF2 descendant-scope: clip を子孫 wrapper に置き text を押出し (round-2・visibleTextArea の per-fragment+全clip-chain で捕捉)
        ("srs-census-descendant.html", 1280, "light", {"census-omission"}, base),
        # FF2 descendant opacity: 子孫 span に opacity:0 で ink 抹消 (round-3b・visibleTextArea の降下連鎖 opacity 積で捕捉)
        ("srs-census-descopacity.html", 1280, "light", {"census-omission"}, base),
        # FF2 descendant clip-path: 子孫 span に clip-path:inset(100%) (round-3b・visibleTextArea の降下連鎖 clip-path で捕捉)
        ("srs-census-descclip.html", 1280, "light", {"census-omission"}, base),
        # FF2 descendant visibility:hidden: 子孫 span に visibility:hidden (round-3c・rect 有・非paint を text 親 computed visibility で捕捉)
        ("srs-census-descvis.html", 1280, "light", {"census-omission"}, base),
        # --- folio-hef S1 ceiling round-3c (wf_534bb2c7) の収束 fix 回帰 selftest ---
        # FF5 image-sink (CSS-escaped url): \75 rl(data:SVG) を computed-style 正規化 (url("data:...")) で spelling-agnostic 捕捉
        ("srs-census-imgsink-escape.html", 1280, "light", {"image-sink-fabrication"}, base),
        # FF5 image-sink (image-set bare-string): image-set(data:) を computed-style 正規化で捕捉 (url( token 無し綴りを収束)
        ("srs-census-imgsink-imageset.html", 1280, "light", {"image-sink-fabrication"}, base),
        # generated-content ::scroll-button(dir): direction 全変種走査で content 捏造を捕捉 (旧 ::before/after/marker 走査の盲点)
        ("srs-census-scrollbutton.html", 1280, "light", {"pseudo-content-fabrication"}, base),
        # generated-content ::scroll-marker: scroll-marker-group scroller の marker content 捏造を捕捉
        ("srs-census-scrollmarker.html", 1280, "light", {"pseudo-content-fabrication"}, base),
        # FF2 transform:scaleY 縦潰し: 0.4px 高を最小可読高 floor (fontSize×0.4) が非算入 → omission (旧 area-only 閾値の射程穴)
        ("srs-census-squashy.html", 1280, "light", {"census-omission"}, base),
        # FF2 子孫 overflow 微小 band: line-height:1+height:2px の 2px band を最小可読高 floor が非算入 → omission
        ("srs-census-descband.html", 1280, "light", {"census-omission"}, base),
        # --- folio-hef S1 ceiling round-3d (wf_6e852552) の bounded fix 回帰 selftest ---
        # FF5 ::first-letter image-sink: background-image を実描画する ::first-letter (旧 pe 集合外) を pe 拡張で捕捉
        ("srs-census-imgsink-firstletter.html", 1280, "light", {"image-sink-fabrication"}, base),
        # FF5 ::first-line image-sink: ::first-line の background-image を pe 拡張で捕捉
        ("srs-census-imgsink-firstline.html", 1280, "light", {"image-sink-fabrication"}, base),
        # FF2 transform:scaleX 横潰し: 縦 floor を素通る横圧縮を per-char 横密度 floor が omission に倒す
        ("srs-census-squashx.html", 1280, "light", {"census-omission"}, base),
        # FF2 letter-spacing 重畳: transform でない横潰しを per-char 横密度 floor が捕捉
        ("srs-census-smear.html", 1280, "light", {"census-omission"}, base),
        # --- folio-hef S1 ceiling round-3e (wf_27813514) → round-3f bounded fix の回帰 selftest ---
        # list-marker var(): list-style-type:var(--x) で文字列 marker (静的 ban 回避) を render 側 computed-style census が捕捉
        ("srs-census-listmarker.html", 1280, "light", {"list-marker-fabrication"}, base),
        # FF2 word-spacing avg-gaming (Attack E): 空白膨張で node-average を持ち上げる gaming を per-glyph (空白除外) が捕捉
        ("srs-census-wordspace.html", 1280, "light", {"census-omission"}, base),
        # FF2 CJK letter-spacing -0.80em (Attack B): CJK stroke 融合 (advance 0.2fs) を script-aware per-glyph (CJK 0.5fs) が捕捉
        ("srs-census-cjkcrush.html", 1280, "light", {"census-omission"}, base),
        # FF2 scaleY(0.34) (Attack D): 縦 floor 6.4px 直上潰しを minH 0.5 bump (8px) が捕捉
        ("srs-census-squashy034.html", 1280, "light", {"census-omission"}, base),
        # --- folio-hef S1 ceiling round-3f (wf_20e96424) → round-3g bounded fix の回帰 selftest ---
        # bidi escape: unicode-bidi:\62 idi-override (静的 ban 回避) を render 側 computed unicode-bidi census が捕捉
        ("srs-census-bidiescape.html", 1280, "light", {"bidi-override-fabrication"}, base),
        # char overlap: per-char span 分割 + 負 margin 重畳 (各字 natural advance) を element union-vs-sum coverage が捕捉
        ("srs-census-charoverlap.html", 1280, "light", {"census-omission"}, base),
        # @counter-style builtin override: lower-roman 再定義 (computed は allowlist 名のまま) を CSSOM CSSCounterStyleRule census が捕捉
        ("srs-census-counterstyle.html", 1280, "light", {"list-marker-fabrication"}, base),
    ]
    ok = True
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        pages: dict[tuple, object] = {}
        for name, width, scheme, expect, counts in cases:
            key = (width, scheme)
            if key not in pages:
                height = next((h for w, h in VIEWPORTS if w == width), 900)
                pages[key] = browser.new_page(viewport={"width": width, "height": height}, color_scheme=scheme)
            page = pages[key]
            cc = dict(counts)
            pc = cc.pop("plain", None)
            payload = {"counts": cc}
            if pc is not None:
                payload["plainCount"] = pc
            expect_json = json.dumps(payload, ensure_ascii=False)
            result = census(page, f"{base_url}/render-fixtures/{name}", expect_json)
            kinds = {v["kind"] for v in result["violations"]}
            # 全 case で「clean 期待なら totalVisible==totalExpected」「omission 期待なら totalVisible>0 だが <expected」
            # を併せ確認し、 render 破綻 (全件 0) を「clean」と取り違える tautology を塞ぐ。
            rendered = result["totalVisible"] > 0
            passed = rendered and kinds == expect
            ok = ok and passed
            verdict = "PASS" if passed else "FAIL"
            exp = "+".join(sorted(expect)) or "clean"
            got = ("+".join(sorted(kinds)) or "clean") if rendered else f"render 破綻 (可視 {result['totalVisible']})"
            print(f"  [census-selftest {verdict}] {name}@{width}px/{scheme}: 期待={exp} / 実際={got} (可視 {result['totalVisible']}/{result['totalExpected']})")
        browser.close()
    print()
    if ok:
        print("census-selftest: PASS — pseudo-content-fabrication (2b8) / census-omission (459) が kind 完全一致で "
              "発火し、 clean を誤検出せず、 viewport/scheme 直積 plumbing と fail-closed (totalVisible>0) が固定されている")
        return 0
    print("census-selftest: FAIL — census detector が期待通り動作しない (playwright/chromium 版 drift?)")
    return 1


def main() -> int:
    ap = argparse.ArgumentParser(description="folio SRS render-gate (gate F) + render census (sibling)")
    ap.add_argument("html", nargs="?", help="生成 SRS HTML (単一ファイル)。 --selftest 時は不要")
    ap.add_argument("--selftest", action="store_true", help="fixture で detector を自己検証")
    ap.add_argument("--census", action="store_true",
                    help="gate F でなく render census (描画後 content-fidelity: pseudo-content 捏造 / omission) を検査")
    ap.add_argument("--expect", default="",
                    help="census 期待件数 'comp=N,comp=N' (caller が contract から導出)。 --census 時必須")
    ap.add_argument("--vocab", default="",
                    help="census closure 語彙 SSoT JSON (verify-srs.sh が srs.census-vocab.yaml から導出)。 "
                         "--census 時に probe payload (expect.vocab) へ carry = S4 bijection 基盤 (任意)")
    ap.add_argument("--base-url", default=None, help="外部 http server (html の親 dir 配信必須)")
    ap.add_argument("--screenshot-dir", default=None, help="screenshot 保存先 (CI artifact 用)")
    args = ap.parse_args()

    shots = Path(args.screenshot_dir) if args.screenshot_dir else None

    # ---- census mode (gate F sibling) ----
    if args.census:
        if args.selftest:
            if args.base_url:
                return run_census_selftest(args.base_url)
            with serve(SCRIPT_DIR) as base_url:
                return run_census_selftest(base_url)
        if not args.html:
            print("render-gate-srs --census: <html> か --selftest が必要", file=sys.stderr)
            return 2
        try:
            counts = parse_expect(args.expect)
        except ValueError as e:
            print(f"render-gate-srs --census: {e}", file=sys.stderr)
            return 2
        if not counts:
            print("render-gate-srs --census: --expect 'comp=N,...' が必要 (期待件数なしでは census は無意味)", file=sys.stderr)
            return 2
        # --vocab (census closure 語彙 SSoT・folio-hef.3) は任意。 与えられたら JSON を validate し
        # (serve 前 = browser-free fail-closed)、 payload へ carry する。 不正 JSON は tool error。
        vocab = None
        if args.vocab:
            try:
                vocab = json.loads(args.vocab)
            except (ValueError, TypeError) as e:
                print(f"render-gate-srs --census: --vocab JSON 不正: {e}", file=sys.stderr)
                return 2
            if not isinstance(vocab, dict):
                print("render-gate-srs --census: --vocab は JSON object であること", file=sys.stderr)
                return 2
        html = Path(args.html).resolve()
        if not html.is_file():
            print(f"render-gate-srs --census: html not found: {html}", file=sys.stderr)
            return 2
        if args.base_url:
            return run_census(args.base_url, html.name, counts, shots, vocab)
        with serve(html.parent) as base_url:
            return run_census(base_url, html.name, counts, shots, vocab)

    # ---- gate F (visual 健全性) ----
    if args.selftest:
        if args.base_url:
            return run_selftest(args.base_url)
        with serve(SCRIPT_DIR) as base_url:
            return run_selftest(base_url)

    if not args.html:
        print("render-gate-srs: <html> か --selftest が必要", file=sys.stderr)
        return 2
    html = Path(args.html).resolve()
    if not html.is_file():
        print(f"render-gate-srs: html not found: {html}", file=sys.stderr)
        return 2

    if args.base_url:
        return run(args.base_url, html.name, shots)
    with serve(html.parent) as base_url:
        return run(base_url, html.name, shots)


if __name__ == "__main__":
    sys.exit(main())
