# folio plugin — bin/

Phase X1 placeholder. CLI executables will be implemented in Phase X2.

## Planned executables

| executable | role |
|---|---|
| `folio` | Top-level CLI wrapper. Subcommands: `folio validate`, `folio init`, `folio doctor`. Invokes scripts in `../scripts/`. |

When the plugin is installed, this directory is added to PATH so the `folio` command is available from any consumer project's shell.
