# folio plugin — scripts/

Phase X1 placeholder. CI check scripts will be implemented in Phase X2.

## Planned scripts

| script | enforces principle | invoked from |
|---|---|---|
| `link-integrity.py` | P-6 (no orphan, no broken link) | PostToolUse hook + `folio-validate` skill |
| `orphan-check.py` | P-6 (orphan detection) | same |
| `declarative-check.py` | P-4 (declarative form, no past/future narration) | same |
| `what-only-check.py` | P-3 / P-11 (platform-specific HOW detection) | same |
| `caller-marker-check.sh` | rules.html §10.1 REQ-CM-003 (caller marker env var presence) | PreToolUse hook |

All scripts are platform-neutral (Python or shell) and consume `folio.config.yaml` from the consumer project root.

## Reference

Spec for these scripts is defined in [`folio-self-spec.html` §7.5 CI Gate Specification](../../folio-self-spec.html#s7-5-ci-gate) (informative design)。 6 gate の MUST 規範 (REQ-CI-001 + REQ-CI-010〜015) は [`rules.html` §10.2 CI Gate Compliance](../../rules.html#s10-2) を参照。
