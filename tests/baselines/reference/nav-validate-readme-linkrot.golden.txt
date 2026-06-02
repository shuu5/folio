folio validate — link-integrity + jsonld + broken-reverse + vocabulary + delta-marker + ears-coverage + dual-audience + xref + nav (ADR-0020/0025/0028/0033/0034/0035)
root: tests/fixtures/nav-validate-readme-linkrot
files checked: 4 · relations checked: 0
  [OK] internal link-integrity
  [OK] jsonld structural
  [OK] broken-reverse
  [SKIP] vocabulary (forbidden synonym 無し = opt-in)
  [OK] delta-marker
  [OK] dual-audience-structural
  [OK] xref-resolve
  [OK] xref-uniqueness
  [OK] xref-tooltip-consistency
  [SKIP] xref-completeness (folio-xref-completeness=enabled doc 無し = opt-in)
  [SKIP] glossary (vocabulary.yaml definition 無し = opt-in)
  [SKIP] nav-regen-drift (folio-generated index.html 無し = keystone)
  [SKIP] nav-dead-link (生成 index 無し)
  [FAIL] cluster-reachability
  [OK] ears-coverage

violations (1):
  spec/README.html [cluster-reachability] README href "../research/README.html" -> ../research/README.html (link-rot: target not found)
