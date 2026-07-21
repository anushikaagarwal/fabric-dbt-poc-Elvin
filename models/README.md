# models/

Contains all dbt models for the `sales_semantic_models` project, split into
three logical layers. Snowflake routing is configured in
`../dbt_project.yml`. All model layers below are ephemeral by default;
opt-out lands in the schemas listed.

1. **`transform/`** — `transform_<name>.sql`. IMPORT + LOGICAL CTEs. Wraps
   `{{ source(...) }}` at the top of each file (see the POC caveat on the
   deferred `ingest/` layer). One transform per publish model; the base
   name matches its publish counterpart. Ephemeral by default; opt-out
   lands in `eio_ingest.sales_transform`.
2. **`publish/`** — `fct_<name>.sql` for facts and `dim_<name>.sql` for
   dimensions. Business-grain marts that reference transform models via
   `{{ ref(...) }}`. Ephemeral by default. Split by sensitivity:
   - **`publish/shared/`** — opt-out lands in `eio_publish.sales_shared`
     (readonly-role accessible).
   - **`publish/private/`** — opt-out lands in `eio_publish.sales_private`
     (restricted access).

   Facts follow a STAR schema: narrow (FKs + measures + intrinsic
   degenerate dims); descriptive attributes live on the conformed dims
   they FK into. Each fact has a sibling
   `fct_<name>.relationships.yml` sidecar documenting its FKs for
   Fabric.
3. **`metrics/`** — `sem_<name>.yml`. dbt Semantic Layer definitions
   (`semantic_models:`, `metrics:`, `saved_queries:`) mirroring publish
   models (`fct_orders.sql` -> `sem_orders.yml`). Flat folder — no
   `shared/private` split. No SQL, no materialization.

Alongside this file:

- `sources.yml` declares the Snowflake `sources:` used by transform models.
- `models.yml` provides documentation and tests for each layer's models
  (transform and publish).

See `../knowledge_base/conventions.md` for the full playbook — layer
responsibilities, naming, reuse-first governance, publish-layer
completeness, and semantic-layer YAML templates.
