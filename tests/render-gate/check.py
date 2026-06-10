#!/usr/bin/env python3
"""folio render-safety ceiling — playwright 視覚 render gate。

architecture/spec/*.html のうち実 mermaid 図 (<pre class="mermaid">) を持つものを headless
chromium で render し、 render 後の DOM 幾何から **flowchart の text-block overlap** を検出する。

folio validate (pure-bash floor、 REQ-VER-021) は render 後の DOM を見れないため「既知の
overlap-prone パターン (subgraph 多行タイトル)」を static pattern-lint するに留まる。 本 gate は
実ブラウザ render を行い、 flowchart の cluster/node/label 矩形に対する幾何 overlap + clip (多行
cluster-label / label-over-node / node-over-node / content-clipped の 4 class、 probe.js 参照) を
捕捉する ceiling 層。 幾何対象 (.node/.cluster) を持たない図型 (sequence 等) は vacuous、 .node は
持つが flowchart でない図型 (stateDiagram 等 — .node を「出す」ため構造だけでは区別できない) は
uncalibrated として、 いずれも warning で可視化する (silent pass にしない — README「限界」節)。

決定性: mermaid は repo に vendored、 playwright 版は requirements.txt で pin、 **CI は font も pin**
(ci.yml が fonts-noto-cjk を install) するため layout + text shaping が固定される。 detector の主軸
(多行 cluster-label の height) は font-size 駆動で行数に比例するため font 差に頑健。 面積比 detector は
text 幅依存だが、 mermaid dagre layout が node box を label 幅に合わせ self-normalize するため
conservative threshold (0.15 / 0.30) を跨ぎにくい (clean corpus で実測 0、 摂動試験でも frac 不変)。

完全性: render 不足 (期待図数に満たない) は **見逃しでなく失敗** に倒す (fail-closed)。 settle 待ちは
期待 svg 本数到達を polling する。 overlap か render 不足が 1 件でもあれば exit 1 (CI merge block)。
constitution.html は編集禁止の不変資産 (CLAUDE.md §2、 P-10) ゆえ overlap 検出時に救済不能 (frozen
deadlock) になるため **advisory (non-blocking)** で扱い、 floor の FolioConstitution carve-out に倣う。

usage:
  python3 tests/render-gate/check.py            # 全 spec を sweep
  python3 tests/render-gate/check.py --selftest # detector の検出力を fixture で自己検証
  python3 tests/render-gate/check.py --base-url http://127.0.0.1:8777  # 外部 server (REPO_ROOT 配信必須)
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
# 自身の doc @type が FolioConstitution か (= constitution 本体)。 単なる参照 (README/relations が
# constitution を mention する等) では一致しない。 floor (bin/folio) の jq @type 判定と同基準。
CONSTITUTION_TYPE = re.compile(r'"@type"\s*:\s*"FolioConstitution"')


def discover_targets(spec_dir: Path) -> list[dict]:
    """実 mermaid block を含む HTML を {path, expected, blocking} で返す。

    - expected = 実 <pre class="mermaid"> の出現数 (prose 内 escaped は数えない)。 完全性照合に使う。
    - blocking = False は constitution (FolioConstitution、 編集禁止の不変資産)。 advisory 扱い。
      floor (folio validate) が @type==FolioConstitution を scan 除外するのと同じ carve-out。
    """
    targets = []
    for html in sorted(spec_dir.glob("*.html")):
        text = html.read_text(encoding="utf-8")
        # HTML コメント内の <pre class="mermaid"> は DOM に出ず mermaid が render しないため数えない
        # (over-count すると render 不足と誤判定し blocking gate を false-fail させる)。
        live = re.sub(r"<!--.*?-->", "", text, flags=re.DOTALL)
        n = live.count(MERMAID_BLOCK)
        if n == 0:
            continue
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


def fmt_violations(rel: str, result: dict) -> list[str]:
    lines = []
    for d in result["diagrams"]:
        for v in d["violations"]:
            where = f"{rel} · {d.get('caption') or d.get('id') or ('図#' + str(d['idx'] + 1))}"
            detail = ", ".join(f"{k}={v[k]}" for k in v if k != "kind")
            lines.append(f"  [render-safety/ceiling] {v['kind']}: {where} ({detail})")
    return lines


def run_sweep(base_url: str, targets: list[dict]) -> int:
    failures: list[str] = []  # blocking な overlap / render 不足
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1280, "height": 900})
        for t in targets:
            rel = t["path"].relative_to(REPO_ROOT).as_posix()
            expected, blocking = t["expected"], t["blocking"]
            result = probe_page(page, f"{base_url}/{rel}", expected)
            got = result["svgCount"]
            n = sum(len(d["violations"]) for d in result["diagrams"])
            tag = "" if blocking else " [advisory]"
            short = got < expected  # render 不完全 = 見逃しリスク
            status = "FAIL" if (n or short) else "OK"
            note = f" (render 不足: {got}/{expected})" if short else ""
            print(f"  [{status}]{tag} {rel} — {got}/{expected} 図 / {n} overlap{note}")
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
            if not blocking:
                continue  # constitution は advisory: 表示のみ、 exit に影響させない
            if short:
                failures.append(f"  [render-safety/ceiling] incomplete-render: {rel} ({got}/{expected} 図 — 全図 render 前に probe)")
            failures += fmt_violations(rel, result)
        browser.close()
    print()
    if failures:
        print(f"render-safety ceiling: {len(failures)} 件の問題 (幾何 overlap / render 不足)\n")
        print("\n".join(failures))
        return 1
    print("render-safety ceiling: clean — 0 overlap (全図 render 確認済)")
    return 0


def run_selftest(base_url: str) -> int:
    """detector の検出力を fixture で自己検証する (mermaid/chromium 版変化への回帰ガード)。

    各 case は (fixture, 期待図数, 期待 violation kind 集合, 期待 coverage)。 判定は 2 軸とも厳密:
    - kind は **完全一致** (subset でない) — 期待した detector「だけ」が発火することを要求する。
      subset 判定だと positive fixture 上の予期せぬ誤発火 (別 detector の偽陽性) が masking される。
      随伴発火 (multiline fixture の cluster-label-over-node 等) は期待集合に明記して許容集合を閉じる。
    - coverage は full / vacuous / uncalibrated の 3 値一致 — 非 flowchart 図の可視化経路も固定する。
    render 不足 (svgCount < 期待図数) はどの case でも FAIL に倒す — 「壊れて何も render しない」を
    「clean」と取り違えない (tautology escape hatch を塞ぐ)。
    """
    fix = Path(__file__).resolve().parent / "fixtures"
    cases = [
        # 実 mermaid render を通す fixture (mermaid/chromium 版 drift への回帰ガード):
        ("multiline-subgraph.html", 1, {"cluster-label-multiline", "cluster-label-over-node"}, "full"),  # detector(1) + 随伴(2)
        ("single-line-subgraph.html", 1, set(), "full"),                       # clean (誤検出なし)
        ("scaled-multiline-subgraph.html", 1, {"cluster-label-multiline", "cluster-label-over-node"}, "full"),  # detector(1) の scale<1 正規化
        ("nonflowchart-vacuous.html", 1, set(), "vacuous"),                    # sequence → clean かつ vacuous 報告
        ("state-uncalibrated.html", 1, set(), "uncalibrated"),                 # state は .node を出す → uncalibrated 報告
        # 合成 SVG fixture (mermaid は通常この欠陥を生成しないため、 mermaid 出力と同じ class 構造の
        # SVG を直置きして detector arm 自体を検証する):
        ("node-overlap.html", 1, {"node-over-node"}, "full"),                  # detector(3)
        ("clipped-content.html", 1, {"content-clipped"}, "full"),              # detector(4)
        ("label-over-node.html", 1, {"label-over-foreign-node"}, "full"),      # detector(2) 単独 arm
    ]
    ok = True
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1280, "height": 900})
        for name, expected, expect_kinds, expect_cov in cases:
            rel = (fix / name).relative_to(REPO_ROOT).as_posix()
            result = probe_page(page, f"{base_url}/{rel}", expected)
            got = result["svgCount"]
            kinds = {v["kind"] for d in result["diagrams"] for v in d["violations"]}
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
            print(f"  [selftest {verdict}] {name}: 期待={exp} / 実際={got_s}")
        browser.close()
    print()
    if ok:
        print("selftest: PASS — 全 detector arm が kind 完全一致で発火し、 clean を誤検出せず、 scale 正規化と coverage 分類 (vacuous/uncalibrated) が固定されている")
        return 0
    print("selftest: FAIL — detector が期待通り動作しない (mermaid/chromium 版 drift?)")
    return 1


def main() -> int:
    ap = argparse.ArgumentParser(description="folio render-safety ceiling (playwright render gate)")
    ap.add_argument("--root", default="architecture/spec", help="spec HTML ディレクトリ (REPO_ROOT 相対)")
    ap.add_argument("--base-url", default=None, help="外部 http server (REPO_ROOT 配信必須、 未指定なら自前起動)")
    ap.add_argument("--selftest", action="store_true", help="fixture で detector を自己検証")
    args = ap.parse_args()

    def go(base_url: str) -> int:
        if args.selftest:
            return run_selftest(base_url)
        spec_dir = REPO_ROOT / args.root
        targets = discover_targets(spec_dir)
        if not targets:
            print(f"対象 mermaid 図なし: {args.root}")
            return 0
        nb = sum(1 for t in targets if t["blocking"])
        na = len(targets) - nb
        adv = f" (+ advisory {na})" if na else ""
        print(f"render-safety ceiling — {nb} ファイル{adv}を headless chromium で render\n")
        return run_sweep(base_url, targets)

    if args.base_url:
        return go(args.base_url)
    with serve(REPO_ROOT) as base_url:
        return go(base_url)


if __name__ == "__main__":
    sys.exit(main())
