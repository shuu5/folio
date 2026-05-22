# folio plugin — static/

Phase X1 placeholder. Static assets bundled with the plugin (for skill/agent consumption) will be added in Phase X2.

## Note on mermaid.min.js

The Mermaid vendor is located at `architecture/assets/mermaid.min.js` (folio repo root level), referenced directly by `constitution.html`, `rules.html`, and `folio-self-spec.html` (and any future Layer 0 HTML file with mermaid diagrams). The plugin does not duplicate it; consumer projects load Mermaid via the folio repo's own HTML files when previewing folio spec, and choose their own diagram rendering strategy for their `architecture/spec/*.html` files.
