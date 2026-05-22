# folio plugin — scripts/

Phase X1 placeholder. CI check scripts will be implemented in Phase X2.

## Planned scripts

| script | enforces principle | invoked from |
|---|---|---|
| `link-integrity.py` | P-6 (no orphan, no broken link) | PostToolUse hook + `folio-validate` skill |
| `orphan-check.py` | P-6 (orphan detection) | same |
| `declarative-check.py` | P-4 (declarative form, no past/future narration) | same |
| `what-only-check.py` | P-3 / P-11 (platform-specific HOW detection) | same |
| `caller-marker-check.sh` | P-13 (caller marker env var presence) | PreToolUse hook |

All scripts are platform-neutral (Python or shell) and consume `folio.config.yaml` from the consumer project root.

## Reference

Spec for these scripts is defined in [`architecture-rules.html` §7.5 CI Gate Specification](../../architecture-rules.html).
