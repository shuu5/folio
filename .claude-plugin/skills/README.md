# folio plugin — skills/

Phase X1 placeholder. 8 skills will be implemented in Phase X2.

## Planned skills

| skill | role | invoked by |
|---|---|---|
| `folio-init` | Scaffold a new Layer 1 consumer project (generate `folio.config.yaml`, `architecture/` skeleton) | user (via `/folio:init`) |
| `folio-architect` | Run the 7-phase PR cycle (Discovery → Summary) for spec edit | user (via `/folio:architect`) |
| `folio-spec-edit` | Single-file spec edit dispatch (Phase E only) | folio-architect or user |
| `folio-validate` | Run local CI gate (link integrity, declarative form, what-only, vocabulary, EARS coverage, delta marker consistency) | user (via `/folio:validate`) |
| `folio-review-vocabulary` | Phase F vocabulary specialist review | folio-architect Phase F |
| `folio-review-structure` | Phase F structure specialist review | folio-architect Phase F |
| `folio-review-ssot` | Phase F SSoT specialist review | folio-architect Phase F |
| `folio-review-temporal` | Phase F temporal specialist review | folio-architect Phase F |

## Reference

Spec for these skills is defined in [`architecture-rules.html` §7 Harness Layer Components](../../architecture-rules.html).
