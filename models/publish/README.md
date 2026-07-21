# publish/

Business-grain mart models that surface transform-layer outputs to BI
consumers (Power BI, Looker). Ephemeral by default, so each file is a
thin `SELECT` from a transform model:

```sql
SELECT * FROM {{ ref('transform_<name>') }}
```

## Naming

- `fct_<name>.sql` — fact models (event/transaction grain, contains
  additive measures). Narrow by convention: only FKs, measures, and
  intrinsic degenerate dims.
- `fct_<name>.relationships.yml` — Fabric relationships sidecar sitting
  next to each fact. One entry per FK on the fact. See
  `../../knowledge_base/conventions.md` §2.6.
- `dim_<name>.sql` — conformed dimension models (attributes only, no
  measures). Reused across every fact that touches the entity. See
  `../../knowledge_base/conventions.md` §2.4.
- Sensitivity is indicated by the containing folder, not by a filename
  suffix. Dims carrying PII (e.g. `dim_unified_contact`) live in
  `private/` even when facts that FK into them live in `shared/` — the
  FK itself is not PII.

## Sub-folders

- **`shared/`** — opt-out lands in `eio_publish.sales_shared` (readonly
  role). Anything a downstream BI dashboard or dbt project consumes
  belongs here.
- **`private/`** — opt-out lands in `eio_publish.sales_private`
  (restricted). Use for models with sensitive attributes.

Because models are ephemeral by default, the `shared`/`private` split is
organizational documentation only — enforcement requires a materialized
downstream object. See the POC caveats in `../../AGENTS.md`.

Schema and database routing (for opt-outs) is configured centrally in
`../../dbt_project.yml` under `models.sales_semantic_models.publish`.
