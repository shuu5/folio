#!/usr/bin/env python3
"""folio SRS render-gate (taxonomy §5.2 gate F) — 生成 SRS プレゼン HTML の決定的 render 健全性検査。

verify-srs.sh (gate A-E,G,H + visual-first) は pure-bash で render 後の DOM を見れないため、 本 gate が
headless chromium で実 render し、 probe-srs.js で 3 class を検出する:
  (1) horizontal-overflow — 意図しない document 横スクロール
  (2) component-overlap   — data-component block 同士の矩形交差
  (3) low-contrast        — text↔実効背景の WCAG AA 未満 (S3 で手検出した dark-contrast 崩壊型)
検査は **light / dark 両 color-scheme × 3 viewport (375/768/1280)** の直積で行う。 dark 専用の崩れ
(色トークンの dark override 漏れ等) は dark を実際に emulate しないと捕れない (S3 の実欠陥がこの class)。

既存 folio render-gate (tests/render-gate/check.py、 mermaid flowchart 専用・corpus sweep) とは別系統。
本 gate は単一 SRS HTML を対象にし、 生成 SRS 固有の color/overflow/overlap を見る。 幾何定数 (横溢れ許容・
overlap 面積比) は probe.js (ADR-0037) の値を probe-srs.js が複製する (drift は test-adversarial A35 が検知)。

被覆限界 (honest disclosure): taxonomy §5.2 gate F は「overlap / 横幅超過 / 不可視化」を掲げるが、 本実装の
「不可視化」検出は **low-contrast (読めない=実質不可視) のみ**。 clip / visibility:hidden / overflow:hidden に
よる *物理的* invisibility (mermaid probe.js の content-clipped 相当) は未対応 — 必須部品が CSS バグで丸ごと
不可視化しても violation でなく検査対象外になる (visible() を除外 filter として使うため)。 これは ADR-0037 が
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


def main() -> int:
    ap = argparse.ArgumentParser(description="folio SRS render-gate (gate F)")
    ap.add_argument("html", nargs="?", help="生成 SRS HTML (単一ファイル)。 --selftest 時は不要")
    ap.add_argument("--selftest", action="store_true", help="fixture で detector を自己検証")
    ap.add_argument("--base-url", default=None, help="外部 http server (html の親 dir 配信必須)")
    ap.add_argument("--screenshot-dir", default=None, help="screenshot 保存先 (CI artifact 用)")
    args = ap.parse_args()

    shots = Path(args.screenshot_dir) if args.screenshot_dir else None

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
