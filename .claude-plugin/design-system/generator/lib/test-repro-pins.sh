#!/usr/bin/env bash
# folio 敵対 suite 共通: repro-build byte-identity gate (verify_repro_build・folio-mzn.3 Phase B / folio-3d23 B3)
# の conformance seed。 各 pack 敵対 suite が source し repro_pins を 1 回呼ぶ。 sub-pin (a)-(d) を echo し、
# 全 pass で return 0 / 1 個でも逸脱で return 1 (fail-closed)。 呼出元 suite は自身の ok/ng で結果を畳む。
#
# なぜ suite 側は bulk case で SKIP_REPRO=1 (honest skip) か: repro-build arm は verify-*.sh 既定 ON ゆえ、
# arm 未 skip だと敵対 suite の全 case で assemble→inject 再 build が走り 10 分/suite を超える (実測: srs suite が
# 300s timeout)。 gate F の SRS_SKIP_RENDER=1 と同型の honest SKIP idiom (floor 不完全と明示・PASS 詐称せず) で
# bulk を skip し、 本 conformance pin *だけ* を SKIP_REPRO= 明示解除で arm ON 実走させる (arm の意味権威は保つ)。
#
# 4 sub-pin (verification §3.9 REQ-VER-030 conformance):
#   (a) EOF 1-byte 追記      → repro-build:BYTE-DIFF (占有 pin/floor が数えない </html> 後の garbage を byte 差で捕捉 = arm aliveness)
#   (b) footer 時刻のみ別 valid ts へ差替 → [OK] repro-build (時刻正規化で PASS・quotient-map が過度に strict でない)
#   (c) REPRO_PROSE 不在      → exit 2 + TOOLERR] repro-build: prose … 不在 (入力欠落 = 測定系 tool-integrity error・gate 判定と分離)
#   (d) footer 時刻を非数値 'HACKED' へ改竄 → repro-build:BYTE-DIFF (strict regex が footer 内の *非 timestamp* 改竄を masking しない
#                            = 正規化を過緩化した mutant [生成: <b>[^<]*</b>] なら PASS 詐称する箇所を strict regex は FAIL させる)
# (b)+(d) が正規化 regex を両側から挟む: (b)=valid ts は畳む (過 strict でない) / (d)=非 ts 改竄は畳まない (過緩でない) = mutation-kill 相当。
#
# usage: repro_pins <verify.sh> <pack> <contract> <prose> <assemble.sh> <inject.sh> [verify-mode-args...]
#   verify-mode-args = genuine filled HTML を verify が受理する mode (srs=無し / 他 pack=--filled <prose>)。
#   前提: SKIP_REPRO は呼出元 suite が export 済でも本 helper が各 verify 呼出しで空へ上書きし arm を ON にする。
repro_pins() {
  local verify="$1" pack="$2" contract="$3" prose="$4" asm="$5" inj="$6"; shift 6
  local -a mode=( "$@" )
  local d rc=0 out ec
  d="$(mktemp -d)"
  # genuine filled build (assemble → inject)。 setup 失敗は fail-closed (return 1)。
  # ★assemble は stdout redirect で受ける (assemble-glossary.sh は OUT 引数非対応・stdout 専用ゆえ全 pack 統一)。
  if ! bash "$asm" "$contract" > "$d/a.html" 2>/dev/null; then echo "  [rfail] ($pack) setup: assemble 非零 exit"; rm -rf "$d"; return 1; fi
  if ! bash "$inj" "$prose" "$d/a.html" "$d/f.html" >/dev/null 2>&1; then echo "  [rfail] ($pack) setup: inject 非零 exit"; rm -rf "$d"; return 1; fi

  # (a) EOF 1-byte 追記 → BYTE-DIFF。 </html> 後の garbage は floor/占有 pin が数えず repro-build のみ捕捉。
  cp "$d/f.html" "$d/a_tamp.html"; printf 'X' >> "$d/a_tamp.html"
  out="$(SKIP_REPRO= SRS_SKIP_RENDER=1 bash "$verify" "${mode[@]}" "$contract" "$d/a_tamp.html" 2>&1)"
  # ★substring 判定は bash [[ == ]] で行う (printf|grep -q は pipefail 下で grep 早期終了→printf SIGPIPE→pipeline 非零の
  #   誤判定を起こす・SIGPIPE race)。 [[ == *lit* ]] は subprocess 無し・決定的・pipefail 免疫。
  if [[ "$out" == *'repro-build:BYTE-DIFF'* ]]; then echo "  [rpass] (a) EOF 1-byte 追記 → repro-build:BYTE-DIFF ($pack)"; else echo "  [rfail] (a) EOF 1-byte 追記が repro-build で捕捉されない ($pack)"; rc=1; fi

  # (b) footer 時刻のみ別 valid ts へ → [OK] repro-build (正規化で byte-identity・過 strict でない)。
  perl -0777 -pe 's{生成: <b>[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}</b>}{生成: <b>1999-12-31 23:59</b>}g' "$d/f.html" > "$d/b_ts.html"
  if cmp -s "$d/f.html" "$d/b_ts.html"; then echo "  [rfail] (b) setup: footer 生成時刻の差替先が無い ($pack)"; rc=1; else
    out="$(SKIP_REPRO= SRS_SKIP_RENDER=1 bash "$verify" "${mode[@]}" "$contract" "$d/b_ts.html" 2>&1)"
    if [[ "$out" == *'repro-build: 再 build byte-identity'* && "$out" != *'repro-build:BYTE-DIFF'* ]]; then echo "  [rpass] (b) 時刻のみ差 → [OK] repro-build ($pack)"; else echo "  [rfail] (b) 時刻のみ差が [OK] repro-build にならない ($pack)"; rc=1; fi
  fi

  # (c) REPRO_PROSE 不在 → exit 2 + TOOLERR (入力欠落 = 測定系 tool-integrity error)。
  out="$(SKIP_REPRO= REPRO_PROSE="$d/NOEXIST.prose.yaml" SRS_SKIP_RENDER=1 bash "$verify" "${mode[@]}" "$contract" "$d/f.html" 2>&1)"; ec=$?
  if [[ "$ec" -eq 2 && "$out" == *'TOOLERR] repro-build: prose manifest 不在'* ]]; then echo "  [rpass] (c) 入力欠落 → exit 2 tool-integrity error ($pack)"; else echo "  [rfail] (c) 入力欠落が exit 2+TOOLERR にならない (ec=$ec・$pack)"; rc=1; fi

  # (d) footer 時刻を非数値 'HACKED' へ → BYTE-DIFF (strict regex が footer 内の非 timestamp 改竄を masking しない)。
  perl -0777 -pe 's{生成: <b>[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}</b>}{生成: <b>HACKED</b>}g' "$d/f.html" > "$d/d_hack.html"
  if cmp -s "$d/f.html" "$d/d_hack.html"; then echo "  [rfail] (d) setup: footer 生成時刻の改竄先が無い ($pack)"; rc=1; else
    out="$(SKIP_REPRO= SRS_SKIP_RENDER=1 bash "$verify" "${mode[@]}" "$contract" "$d/d_hack.html" 2>&1)"
    if [[ "$out" == *'repro-build:BYTE-DIFF'* ]]; then echo "  [rpass] (d) 非 ts footer 改竄 → repro-build:BYTE-DIFF (masking 防止) ($pack)"; else echo "  [rfail] (d) 非 ts footer 改竄を repro-build が masking した ($pack)"; rc=1; fi
  fi

  rm -rf "$d"
  return $rc
}
