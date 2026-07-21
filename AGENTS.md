# AGENTS.md — sales_semantic_models

Entrypoint for AI coding agents (Cursor, Codex, Claude Code, ...) working in
`dags/dbt/sales_semantic_models/`. Auto-loaded for every file in this
subtree. Keep this file concise; deeper reference material lives in
`knowledge_base/`.

## Purpose

The `sales_semantic_models` dbt project hosts the semantic-layer definitions
(entities, dimensions, measures, metrics) for the **sales** data domain, plus
the transform and publish models the semantic layer references. Downstream
consumers are Power BI (DAX) and Looker (LookML).

## Workflow

When an analyst provides a full SQL statement, produce the corresponding
layered dbt model set:

1. Identify every upstream table the SQL references.
2. For each table:
   - If already declared in `models/sources.yml`, use it as-is.
   - Otherwise, add a new `source:` entry pointing at the correct
     `database.schema.table`. Source `name:` must equal the Snowflake schema
     name (repo convention).
3. Classify the target as a **fact** (`fct_*`, has additive measures at
   its grain) or **dimension** (`dim_*`, describes an entity with
   attributes and no measures). For facts, split the output columns into
   foreign keys, measures, intrinsic degenerate dimensions, and
   descriptive attributes to offload to conformed dims (STAR schema).
4. For every descriptive-attribute bucket on a fact, decide whether the
   required dim already exists under `models/publish/{shared,private}/`.
   Reuse where possible; extend the existing dim if it is missing a
   column; only create a new dim when no existing one covers the entity.
5. Decompose the SQL into layered dbt models:
   - `models/transform/transform_<name>.sql` — IMPORT + LOGICAL CTEs.
     One transform per publish model. Wraps `{{ source(...) }}` at the
     top. Facts stay narrow (FKs + measures + intrinsic degenerate
     dims); descriptive attributes are not projected here.
   - `models/publish/{shared,private}/fct_<name>.sql` or
     `dim_<name>.sql` — one-liner `SELECT * FROM {{ ref(...) }}` on the
     matching transform.
   - For every fact, add
     `models/publish/{shared,private}/fct_<name>.relationships.yml` —
     Fabric-format relationships sidecar with one entry per FK on the
     fact.
6. Add `models/metrics/sem_<name>.yml` mirroring the publish model
   (`fct_orders.sql` → `sem_orders.yml`). Foreign entities correspond to
   the fact's FK columns. See §3 of `knowledge_base/conventions.md`.
7. Add descriptions and tests in `models/models.yml` for every new or
   changed transform / publish model. Every fact FK column gets a
   `relationships` test (severity `warn`) to its target dim's PK. Every
   new dim PK gets `unique` + `not_null`.
8. If the analyst's original SQL is meant to remain queryable as a
   single named handle, add an ephemeral wrapper model that reproduces
   it via `{{ ref(...) }}` calls to the transform / publish outputs.

## Mandatory rules

1. **Ephemeral is the default.** Set project-wide in `dbt_project.yml` for
   `transform`, `publish/shared`, and `publish/private`. Do not add
   `{{ config(materialized='ephemeral') }}` to individual models — it is
   already the default. To opt OUT (e.g. a mart that must be a `table` for
   BI Direct Lake), add `{{ config(materialized='table') }}` with a
   one-line justification comment.
2. **Layer structure**: `models/{transform, publish/{shared,private}, metrics}/`.
   No `models/ingest/` folder yet — sources are referenced directly in
   transform files via `{{ source(...) }}` IMPORT CTEs.
2a. **Intermediate subfolder**: `models/transform/intermediate/` holds
   transforms that union multiple source systems, dedupe, or re-grain
   (e.g. fan-out to line-item grain). Transforms that pass through a
   single source with light renaming/casing stay at `models/transform/`
   root. This mirrors dbt's official staging vs. intermediate split — it
   is **not** a fact-vs-dimension split (dbt explicitly steers away from
   organizing by Kimball fact/dim; see `knowledge_base/conventions.md`
   §2.1a). Filenames and the one-transform-per-publish-model naming rule
   (#4 below) are unaffected by which subfolder a transform lives in.
3. **Naming prefixes**: `transform_*`, `fct_*`, `dim_*`, `sem_*`. Sensitivity
   is indicated by the containing folder (`publish/shared/` vs
   `publish/private/`), not by a filename suffix.
4. **One transform per publish model.** Every `fct_*.sql` and every
   `dim_*.sql` is backed by exactly one `transform_<name>.sql` with the
   matching base name. Never split a publish model into multiple
   transforms. Conformed dims count as their own publish + transform
   pair, not as subordinates of the fact.
5. **STAR schema for facts.** Facts stay narrow: foreign keys +
   measures + intrinsic degenerate dims only. Any attribute that
   describes a business entity (account, employee, contact, opportunity,
   date, ...) must live in that entity's conformed dim, not on the fact.
6. **Reuse conformed dims first.** Before creating any new dim, check
   `models/publish/{shared,private}/dim_*.sql`. Extend an existing dim
   when it covers the entity but is missing a column; only create a new
   dim when no existing one covers the entity.
7. **Fact FK integrity.** Every fact FK column has a `relationships`
   test in `models/models.yml` (severity `warn`) referencing the target
   dim's primary key, **and** a matching entry in the fact's
   `<fact>.relationships.yml` sidecar for Fabric.
8. **Semantic YAML mirroring**: exactly one `sem_<name>.yml` per publish
   model. `metrics/` is flat — no `shared/private` split there.
9. **Every metric has `label` + `description`.** No exceptions. Descriptions
   must state exclusions (e.g. "excludes cancelled orders").
10. **Publish-layer completeness**: every `fct_*` / `dim_*` that BI consumers
    reference must exist, be documented, and cover the required grain,
    keys, and joins.
11. **Golden rule**: never define the same business rule (e.g. "exclude
    cancelled orders") in more than one of dbt / LookML / DAX. If the
    transform or publish layer filters it, do not re-filter downstream.
12. **`ref()` and `source()` always** — never hardcode `database.schema.table`
    in model SQL, `analyses/`, or semantic YAML.
13. **Every dashboard / Explore has a matching dbt `exposure`.**

## Layer → Snowflake routing

Configured centrally in `dbt_project.yml`; do not override in per-model
`{{ config(...) }}` blocks unless justified. All model layers are
ephemeral by default; the `database.schema` values below only apply when
a model opts out of ephemeral.

- `models/transform/*.sql` (incl. `intermediate/`) → ephemeral; opt-out
  lands in `eio_ingest.sales_transform`.
- `models/publish/shared/*.sql` → ephemeral; opt-out lands in `eio_publish.sales_shared`.
- `models/publish/private/*.sql` → ephemeral; opt-out lands in `eio_publish.sales_private`.
- `models/metrics/*.yml` → YAML only; no materialization.
- Test failures → `eio_ingest.sales_test_log` (physical, always materialized).

## Reference files

Load on demand when needed:

- `@dbt_project.yml` — project-level routing, tags, and vars.
- `@models/sources.yml` — Snowflake sources catalog (source: entries only).
- `@models/models.yml` — transform + publish model documentation, tests,
  and current inventory of conformed dims.
- `models/publish/{shared,private}/dim_*.sql` — reusable dim inventory,
  cross-reference before creating any new dim.
- `models/publish/{shared,private}/*.relationships.yml` — Fabric
  relationships shape to match when adding a new fact sidecar.
- `@knowledge_base/conventions.md` — full playbook: layer responsibilities,
  STAR-schema pattern, conformed-dim reuse, semantic-layer YAML templates,
  ad-hoc patterns, end-to-end workflow.

## POC caveats

- **Ephemeral models do not enforce sensitivity.** The `publish/shared` vs
  `publish/private` split is organizational documentation. Access control
  requires a materialized downstream object.
- **`ingest/` layer is deferred.** Sources live in transform IMPORT CTEs
  until the ingest folder is introduced.
- **A time spine model is required for MetricFlow.** Provided by
  `models/transform/metricflow_time_spine.sql` + `.yml` (materialized as a
  view, opts out of the ephemeral default). Do not delete or `ref()` it from
  business models — it exists solely for the semantic layer. See
  `knowledge_base/conventions.md` §1.3.
- **`dbt parse`/`compile`/`build` fail on every ephemeral model backing a
  semantic model — this is not fixed by the time spine.** dbt-core sets
  `relation_name = None` on any ephemeral model; MetricFlow's semantic
  manifest requires a non-null `relation_name` for the model behind each
  `semantic_models:` entry. Since `publish/shared` and `publish/private` are
  ephemeral by default, every full manifest load fails with
  `PydanticSemanticModel node_relation -> relation_name: none is not an
  allowed value`, regardless of correctness of any given model. This is a
  known, by-design dbt-core/MetricFlow limitation, not a per-model bug — do
  not chase it, and do not run dbt CLI commands expecting them to pass while
  this project's layers stay ephemeral.
