# Archive

Runbooks for migrations that are finished. They are kept because they record why
the current shape is what it is, and what the rollback was — not because they
describe anything you should still do.

- `MIGRATION.md` — raw kustomize to the Helm multi-source model. Done.
- `MOTIV_SPLIT.md` — splitting the Motiv agent into its own Application. Done.
- `STORE_SPLIT_PHASE1.md` — scaffolding the Latta Putta / Venu split. Done; both
  brands are live, and the `examples/future-*-values.yaml` files it describes
  have been removed.

Paths in these files predate the chart rename: `charts/venu` is now
`charts/marketplace` and `charts/agents` is now `charts/agent`.
