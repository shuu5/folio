#!/usr/bin/env python3
"""folio render-safety ceiling — playwright 視覚 render gate。

corpus 全 page (repo-root index.html + architecture/**/*.html) を headless chromium で
**3 viewport (375 / 768 / 1280)** で render し、 render 後の DOM 幾何から (a) mermaid flowchart の
text-block overlap (実 <pre class="mermaid"> を持つ page のみ実質発火) と (b) **chrome 崩れ**
(horizontal-overflow / nav-over-content の 2 arm、 ADR-0039 §2.8) を検出する。

folio validate (pure-bash floor、 REQ-VER-021 / REQ-VER-023) は render 後の DOM を見れないため
static pattern-lint に留まる。 本 gate は実ブラウザ render を行い、 flowchart の cluster/node/label
矩形に対する幾何 overlap + clip (多行 cluster-label / label-over-node / node-over-node /
content-clipped の 4 class) に加え、 page-level の chrome 幾何 (本文が viewport を溢れる意図しない
横スクロール / nav landmark と本文の矩形重なり、 probe.js (5)(6)) を捕捉する ceiling 層。 viewport は
375 (mobile) / 768 (tablet) / 1280 (desktop) の 3 点 — chrome 崩れは narrow viewport でのみ発現する
ことが多く、 既存 mermaid detector を multi-viewport で回す「だけ」では捕れない (ADR-0039 §2.8 が
明示却下、 chrome arm 新設が本体)。 幾何対象 (.node/.cluster) を持たない図型 (sequence 等) は vacuous、
.node は持つが flowchart でない図型 (stateDiagram 等 — .node を「出す」ため構造だけでは区別できない)
は uncalibrated として、 いずれも warning で可視化する (silent pass にしない — README「限界」節)。

screenshot: --screenshot-dir を渡すと全 page × 全 viewport の full-page screenshot を保存する。
CI が artifact 化し人間 review の補助に充てる (golden 化はしない — brittle 回避、 ADR-0039 §2.8)。

決定性: mermaid は repo に vendored、 playwright 版は requirements.txt で pin、 **CI は font も pin**
(ci.yml が fonts-noto-cjk を install) するため layout + text shaping が固定される。 detector の主軸
(多行 cluster-label の height) は font-size 駆動で行数に比例するため font 差に頑健。 面積比 detector は
text 幅依存だが、 mermaid dagre layout が node box を label 幅に合わせ self-normalize するため
conservative threshold (0.15 / 0.30) を跨ぎにくい (clean corpus で実測 0、 摂動試験でも frac 不変)。

完全性: render 不足 (期待図数に満たない) は **見逃しでなく失敗** に倒す (fail-closed)。 settle 待ちは
期待 svg 本数到達を polling する。 overlap か render 不足が 1 件でもあれば exit 1 (CI merge block)。
constitution.html は編集禁止の不変資産 (CLAUDE.md §2、 P-10) ゆえ overlap 検出時に救済不能 (frozen
deadlock) になるため **advisory (non-blocking)** で扱い、 floor の FolioConstitution carve-out に倣う。
frozen ADR は chrome arm でも blocking のまま — chrome 崩れの是正経路は共有資産 (common.css / chrome)
側にあり frozen 本文編集なしで直せるため deadlock にならない (README「constitution は advisory」節)。

usage:
  python3 tests/render-gate/check.py            # 全 corpus を 3 viewport で sweep
  python3 tests/render-gate/check.py --selftest # detector の検出力を fixture で自己検証
  python3 tests/render-gate/check.py --screenshot-dir /tmp/render-shots  # screenshot も保存 (CI artifact 用)
  python3 tests/render-gate/check.py --base-url http://127.0.0.1:8777   # 外部 server (REPO_ROOT 配信必須)
"""
from __future__ import annotations

import argparse
import contextlib
import functools
import http.server
import re
import socketserver
import sys
import threading
from pathlib import Path

from playwright.sync_api import sync_playwright

REPO_ROOT = Path(__file__).resolve().parents[2]
PROBE_JS = (Path(__file__).resolve().parent / "probe.js").read_text(encoding="utf-8")
SVG_SELECTOR = "figure.diagram svg, pre.mermaid svg, .mermaid svg"
MERMAID_BLOCK = '<pre class="mermaid">'
# sweep viewport の 3 点 (ADR-0039 §2.8): mobile / tablet / desktop。 高さは代表機 (iPhone SE 系 /
# iPad 縦 / 従来値) — full-page screenshot と縦 scroll page では幾何に効かないが、 決定性のため固定する。
VIEWPORTS = [(375, 667), (768, 1024), (1280, 900)]
# 自身の doc @type が FolioConstitution か (= constitution 本体)。 単なる参照 (README/relations が
# constitution を mention する等) では一致しない。 floor (bin/folio) の jq @type 判定と同基準。
CONSTITUTION_TYPE = re.compile(r'"@type"\s*:\s*"FolioConstitution"')


def discover_targets(corpus_dir: Path) -> list[dict]:
    """corpus 全 page を {path, expected, blocking} で返す (chrome 幾何は全 page が対象)。

    - 対象 = repo-root index.html (landing、 corpus_dir の外) + corpus_dir 配下の再帰 *.html。
      mermaid を持たない page も chrome 幾何 arm (probe.js (5)(6)) の検査対象として sweep する。
    - expected = 実 <pre class="mermaid"> の出現数 (prose 内 escaped・HTML コメント内は数えない)。
      0 の page は mermaid 完全性照合が vacuous なだけで、 chrome 幾何は検査される。
    - blocking = False は constitution (FolioConstitution、 編集禁止の不変資産)。 advisory 扱い。
      floor (folio validate) が @type==FolioConstitution を scan 除外するのと同じ carve-out。
    """
    pages = [p for p in [REPO_ROOT / "index.html"] if p.is_file()]
    pages += sorted(corpus_dir.rglob("*.html"))
    targets = []
    for html in pages:
        text = html.read_text(encoding="utf-8")
        # HTML コメント内の <pre class="mermaid"> は DOM に出ず mermaid が render しないため数えない
        # (over-count すると render 不足と誤判定し blocking gate を false-fail させる)。
        live = re.sub(r"<!--.*?-->", "", text, flags=re.DOTALL)
        n = live.count(MERMAID_BLOCK)
        blocking = not CONSTITUTION_TYPE.search(text)
        targets.append({"path": html, "expected": n, "blocking": blocking})
    return targets


@contextlib.contextmanager
def serve(root: Path):
    """root を配信する http.server を空きポートで起動し、 base URL を yield する。"""

    class QuietHandler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *_args):  # access log を抑制
            pass

    httpd = socketserver.TCPServer(("127.0.0.1", 0), functools.partial(QuietHandler, directory=str(root)))
    port = httpd.server_address[1]
    t = threading.Thread(target=httpd.serve_forever, daemon=True)
    t.start()
    try:
        yield f"http://127.0.0.1:{port}"
    finally:
        httpd.shutdown()
        httpd.server_close()


def probe_page(page, url: str, expected: int) -> dict:
    """url を render し、 期待図数到達まで待ってから probe.js を評価して結果 dict を返す。

    固定待ちでなく『svg 本数 >= expected』を polling する。 期待数に達しなければ timeout 後そのまま
    probe し、 svgCount < expected を caller が render 不足 (fail) として検出する (fail-closed)。
    """
    page.goto(url, wait_until="load")
    try:
        page.wait_for_function(
            "n => document.querySelectorAll('figure.diagram svg, pre.mermaid svg, .mermaid svg').length >= n",
            arg=expected,
            timeout=15000,
        )
    except Exception:
        pass  # 不足のまま probe → caller が shortfall を fail に倒す
    page.wait_for_timeout(150)  # 残りの後処理 (focusable 付与等) の settle
    page.evaluate(PROBE_JS)
    return page.evaluate("() => window.__folioRenderProbe()")


def fmt_violations(where_prefix: str, result: dict) -> list[str]:
    lines = []
    for d in result["diagrams"]:
        for v in d["violations"]:
            where = f"{where_prefix} · {d.get('caption') or d.get('id') or ('図#' + str(d['idx'] + 1))}"
            detail = ", ".join(f"{k}={v[k]}" for k in v if k != "kind")
            lines.append(f"  [render-safety/ceiling] {v['kind']}: {where} ({detail})")
    for v in result["page"]["violations"]:
        detail = ", ".join(f"{k}={v[k]}" for k in v if k != "kind")
        lines.append(f"  [render-safety/ceiling] {v['kind']}: {where_prefix} ({detail})")
    return lines


def screenshot_path(out_dir: Path, rel: str, width: int) -> Path:
    """page × viewport ごとの screenshot 保存先 (rel の / は __ に潰して flat に置く)。

    形式は JPEG (quality 80) — full-page PNG だと corpus 全体で ~287MB (実測) になり CI artifact
    として過大。 人間 review の補助 (golden 比較しない) には JPEG で十分。
    """
    d = out_dir / f"{width}px"
    d.mkdir(parents=True, exist_ok=True)
    return d / (rel.replace("/", "__") + ".jpg")


def run_sweep(base_url: str, targets: list[dict], screenshot_dir: Path | None) -> int:
    failures: list[str] = []  # blocking な overlap / chrome 崩れ / render 不足
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        for width, height in VIEWPORTS:
            print(f"--- viewport {width}×{height} ---")
            page = browser.new_page(viewport={"width": width, "height": height})
            for t in targets:
                rel = t["path"].relative_to(REPO_ROOT).as_posix()
                expected, blocking = t["expected"], t["blocking"]
                result = probe_page(page, f"{base_url}/{rel}", expected)
                got = result["svgCount"]
                n = sum(len(d["violations"]) for d in result["diagrams"])
                c = len(result["page"]["violations"])
                tag = "" if blocking else " [advisory]"
                short = got < expected  # render 不完全 = 見逃しリスク
                status = "FAIL" if (n or c or short) else "OK"
                note = f" (render 不足: {got}/{expected})" if short else ""
                fig = f"{got}/{expected} 図 / {n} overlap / " if expected else ""
                print(f"  [{status}]{tag} {rel} — {fig}chrome {c}{note}")
                # coverage warning (fail にはしないが silent pass を可視化する — 将来 folio が
                # sequence/state 図を足したとき「検査済」と誤認させない):
                #   vacuous      = .node/.cluster 不在で幾何検査が構造的に空振り (sequence 等)
                #   uncalibrated = .node はあるが flowchart でない図型 (state 等)。 幾何は測るが
                #                  threshold は flowchart 較正のため検査済とは言えない
                for d in result["diagrams"]:
                    which = d.get("caption") or d.get("id") or ("図#" + str(d["idx"] + 1))
                    if d.get("vacuous"):
                        print(f"    [warn] vacuous-coverage: {which} (type={d.get('type') or '不明'}) — .node/.cluster 不在で幾何検査の対象外")
                    elif d.get("uncalibrated"):
                        print(f"    [warn] uncalibrated-coverage: {which} (type={d.get('type') or '不明'}) — flowchart 較正外の図型 (幾何は測るが threshold 未較正)")
                if screenshot_dir is not None:
                    # 人間 review の補助 (CI artifact)。 golden 比較はしない — brittle 回避 (ADR-0039 §2.8)。
                    page.screenshot(path=str(screenshot_path(screenshot_dir, rel, width)), full_page=True, type="jpeg", quality=80)
                if not blocking:
                    continue  # constitution は advisory: 表示のみ、 exit に影響させない
                where = f"{rel}@{width}px"
                if short:
                    failures.append(f"  [render-safety/ceiling] incomplete-render: {where} ({got}/{expected} 図 — 全図 render 前に probe)")
                failures += fmt_violations(where, result)
            page.close()
        browser.close()
    print()
    if failures:
        print(f"render-safety ceiling: {len(failures)} 件の問題 (幾何 overlap / chrome 崩れ / render 不足)\n")
        print("\n".join(failures))
        return 1
    print("render-safety ceiling: clean — 0 overlap / 0 chrome 崩れ (3 viewport × 全 page render 確認済)")
    return 0


def run_selftest(base_url: str) -> int:
    """detector の検出力を fixture で自己検証する (mermaid/chromium 版変化への回帰ガード)。

    各 case は (fixture, viewport 幅, 期待図数, 期待 violation kind 集合, 期待 coverage)。 判定は 2 軸とも厳密:
    - kind は **完全一致** (subset でない) — 期待した detector「だけ」が発火することを要求する。
      subset 判定だと positive fixture 上の予期せぬ誤発火 (別 detector の偽陽性) が masking される。
      随伴発火 (multiline fixture の cluster-label-over-node 等) は期待集合に明記して許容集合を閉じる。
      kind 集合は mermaid arm (diagrams) と chrome arm (page) の和 — どちらの誤発火も masking しない。
    - coverage は full / vacuous / uncalibrated の 3 値一致 — 非 flowchart 図の可視化経路も固定する
      (mermaid 図を持たない chrome fixture は diagrams が空 = 既定の full)。
    render 不足 (svgCount < 期待図数) はどの case でも FAIL に倒す — 「壊れて何も render しない」を
    「clean」と取り違えない (tautology escape hatch を塞ぐ)。
    viewport は case ごとに指定する — 同一 fixture を 375 / 768 で走らせる対 (chrome-h-overflow) が
    viewport plumbing 自体の回帰ガードを兼ねる (幅が効いていなければどちらかが FAIL する)。
    """
    fix = Path(__file__).resolve().parent / "fixtures"
    cases = [
        # 実 mermaid render を通す fixture (mermaid/chromium 版 drift への回帰ガード):
        ("multiline-subgraph.html", 1280, 1, {"cluster-label-multiline", "cluster-label-over-node"}, "full"),  # detector(1) + 随伴(2)
        ("single-line-subgraph.html", 1280, 1, set(), "full"),                       # clean (誤検出なし)
        ("scaled-multiline-subgraph.html", 1280, 1, {"cluster-label-multiline", "cluster-label-over-node"}, "full"),  # detector(1) の scale<1 正規化
        ("nonflowchart-vacuous.html", 1280, 1, set(), "vacuous"),                    # sequence → clean かつ vacuous 報告
        ("state-uncalibrated.html", 1280, 1, set(), "uncalibrated"),                 # state は .node を出す → uncalibrated 報告
        # 合成 SVG fixture (mermaid は通常この欠陥を生成しないため、 mermaid 出力と同じ class 構造の
        # SVG を直置きして detector arm 自体を検証する):
        ("node-overlap.html", 1280, 1, {"node-over-node"}, "full"),                  # detector(3)
        ("clipped-content.html", 1280, 1, {"content-clipped"}, "full"),              # detector(4)
        ("label-over-node.html", 1280, 1, {"label-over-foreign-node"}, "full"),      # detector(2) 単独 arm
        # chrome 幾何 fixture (ADR-0039 §2.8 の 2 arm。 合成 page を直置きして arm 自体を検証する):
        ("chrome-h-overflow.html", 375, 0, {"horizontal-overflow"}, "full"),         # detector(5): 600px 固定要素が 375 を溢れる
        ("chrome-h-overflow.html", 768, 0, set(), "full"),                           # 同一 fixture が 768 では clean = viewport plumbing の証明
        ("chrome-scroll-container.html", 375, 0, set(), "full"),                     # 意図された scroll container (#121 wide <pre>) を誤検出しない
        ("chrome-nav-overlap.html", 1280, 0, {"nav-over-content"}, "full"),          # detector(6): absolute nav が本文に被さる
        ("chrome-clean.html", 375, 0, set(), "full"),                                # 実 chrome 構造 (breadcrumb+toggle+本文+prevnext) の clean ガード
    ]
    ok = True
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        pages: dict[int, object] = {}  # viewport 幅 → page (使い回し)
        for name, width, expected, expect_kinds, expect_cov in cases:
            if width not in pages:
                height = next((h for w, h in VIEWPORTS if w == width), 900)
                pages[width] = browser.new_page(viewport={"width": width, "height": height})
            page = pages[width]
            rel = (fix / name).relative_to(REPO_ROOT).as_posix()
            result = probe_page(page, f"{base_url}/{rel}", expected)
            got = result["svgCount"]
            kinds = {v["kind"] for d in result["diagrams"] for v in d["violations"]}
            kinds |= {v["kind"] for v in result["page"]["violations"]}
            cov = "full"
            if any(d.get("vacuous") for d in result["diagrams"]):
                cov = "vacuous"
            elif any(d.get("uncalibrated") for d in result["diagrams"]):
                cov = "uncalibrated"
            rendered = got >= expected
            passed = rendered and kinds == expect_kinds and cov == expect_cov
            if not passed:
                ok = False
            verdict = "PASS" if passed else "FAIL"
            exp = ("+".join(sorted(expect_kinds)) or "clean") + (f"+{expect_cov}" if expect_cov != "full" else "")
            if not rendered:
                got_s = f"render 不足 ({got}/{expected})"
            else:
                got_s = ("+".join(sorted(kinds)) or "clean") + (f"+{cov}" if cov != "full" else "")
            print(f"  [selftest {verdict}] {name}@{width}px: 期待={exp} / 実際={got_s}")
        browser.close()
    print()
    if ok:
        print("selftest: PASS — 全 detector arm (mermaid 4 + chrome 2) が kind 完全一致で発火し、 clean を誤検出せず、 scale 正規化・viewport plumbing・coverage 分類 (vacuous/uncalibrated) が固定されている")
        return 0
    print("selftest: FAIL — detector が期待通り動作しない (mermaid/chromium 版 drift?)")
    return 1


def main() -> int:
    ap = argparse.ArgumentParser(description="folio render-safety ceiling (playwright render gate)")
    ap.add_argument("--root", default="architecture", help="corpus ディレクトリ (REPO_ROOT 相対、 再帰)。 repo-root index.html は常に対象に加える")
    ap.add_argument("--base-url", default=None, help="外部 http server (REPO_ROOT 配信必須、 未指定なら自前起動)")
    ap.add_argument("--selftest", action="store_true", help="fixture で detector を自己検証")
    ap.add_argument("--screenshot-dir", default=None, help="全 page × viewport の full-page screenshot 保存先 (CI artifact 用、 golden ではない)")
    args = ap.parse_args()

    def go(base_url: str) -> int:
        if args.selftest:
            return run_selftest(base_url)
        targets = discover_targets(REPO_ROOT / args.root)
        if not targets:
            print(f"対象 page なし: {args.root}")
            return 0
        nb = sum(1 for t in targets if t["blocking"])
        na = len(targets) - nb
        nm = sum(1 for t in targets if t["expected"])
        adv = f" (+ advisory {na})" if na else ""
        print(f"render-safety ceiling — {nb} page{adv} (うち mermaid {nm}) × {len(VIEWPORTS)} viewport を headless chromium で render\n")
        shots = Path(args.screenshot_dir) if args.screenshot_dir else None
        return run_sweep(base_url, targets, shots)

    if args.base_url:
        return go(args.base_url)
    with serve(REPO_ROOT) as base_url:
        return go(base_url)


if __name__ == "__main__":
    sys.exit(main())
