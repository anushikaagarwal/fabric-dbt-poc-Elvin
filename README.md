# sales_semantic_models

**POC status.** dbt project hosting the semantic-layer definitions for the
**sales** data domain, plus the transform and publish models the semantic
layer references. Downstream BI consumers are Power BI (DAX) and Looker
(LookML).

## Project layout

```
sales_semantic_models/
├── AGENTS.md                   # AI-agent entrypoint (workflow + mandatory rules)
├── knowledge_base/
│   └── conventions.md          # Analytics engineering playbook
├── dbt_project.yml
├── packages.yml
├── .gitignore
├── analyses/                   # ad-hoc SQL - never materialized
├── macros/                     # project-scoped Jinja macros
├── models/
│   ├── sources.yml             # Snowflake sources catalog (sources: only)
│   ├── models.yml              # transform + publish model docs and tests
│   ├── transform/              # transform_<name>.sql
│   ├── publish/
│   │   ├── shared/             # fct_<name>.sql / dim_<name>.sql (readonly-role)
│   │   └── private/            # fct_<name>.sql / dim_<name>.sql (restricted)
│   └── metrics/                # sem_<name>.yml (dbt Semantic Layer)
├── seeds/                      # static reference data
├── snapshots/
└── tests/                      # singular + custom generic tests
```

## Layer routing (Snowflake)

Ephemeral is the project-wide default for `transform`, `publish/shared`,
and `publish/private` (set in `dbt_project.yml`). Ephemeral models compile
into downstream queries as CTEs and do not create physical objects. The
`database.schema` values below apply only when a model opts out of
ephemeral via `{{ config(materialized='...') }}`.

| Layer | Opt-out database.schema | File prefix |
| --- | --- | --- |
| `models/transform/` | `eio_ingest.sales_transform` | `transform_*` |
| `models/publish/shared/` | `eio_publish.sales_shared` | `fct_*` / `dim_*` |
| `models/publish/private/` | `eio_publish.sales_private` | `fct_*` / `dim_*` |
| `models/metrics/` | n/a (YAML only) | `sem_*` |
| Test failures | `eio_ingest.sales_test_log` (always materialized) | n/a |

See [`AGENTS.md`](./AGENTS.md) and
[`knowledge_base/conventions.md`](./knowledge_base/conventions.md).

## Workflow

An analyst provides SQL. An AI agent (or engineer) translates it into the
layered model set:

1. Declare each upstream table in `models/sources.yml`.
2. Plan the STAR: identify the fact's foreign keys and cross-reference
   `models/publish/{shared,private}/dim_*.sql` to decide, per entity,
   reuse / extend / create.
3. Build the fact transform (narrow: FKs + measures + intrinsic dims
   only) and any new/extended dim transforms under `models/transform/`.
   One transform per publish model.
4. Build publish marts under `models/publish/{shared,private}/` —
   `fct_*.sql` / `dim_*.sql` at business grain, each a one-line
   `SELECT * FROM {{ ref(...) }}`.
5. For every new fact, add a `fct_<name>.relationships.yml` sidecar in
   the same folder documenting its FKs (Fabric contract).
6. Add `sem_<name>.yml` under `models/metrics/` mirroring each publish
   model (`fct_orders.sql` -> `sem_orders.yml`).
7. Add descriptions and tests in `models/models.yml`, including a
   `relationships` test (severity `warn`) on every fact FK.
8. Compile, validate, and consume from Power BI / Looker.

Full playbook in `knowledge_base/conventions.md` §5.

## Running locally

Prerequisite:
[Install and Set Up dbt](../documentations/eio_documentation/docs/onboarding/How-Tos/install-and-set-up-dbt.md).

```bash
cd dags/dbt/sales_semantic_models

dbt deps                                    # install local packages
dbt debug                                   # verify Snowflake connection
dbt build --select sales_semantic_models    # seed + run + test the project
```

## POC scope

- Snowflake as the target warehouse (Fabric migration is out of scope).
- Ephemeral is the project-wide default for transform and publish; opt
  out per-model via `{{ config(materialized='...') }}` with a documented
  reason.
- `models/ingest/` is deferred. Sources are referenced directly in
  `models/transform/*.sql` via `{{ source(...) }}`.
- `publish/shared` vs `publish/private` split retained. Note: because
  models are ephemeral by default, sensitivity is organizational
  documentation only — enforcement requires a materialized downstream
  object.
- Airflow auto-DAG is not enabled for this project.

## Reference

- [`AGENTS.md`](./AGENTS.md) — AI-agent entrypoint with workflow and
  mandatory rules.
- [`knowledge_base/conventions.md`](./knowledge_base/conventions.md) —
  analytics engineering playbook (architecture, layer responsibilities,
  semantic-layer YAML templates, ad-hoc analysis, end-to-end workflow).
- [`dbt_project.yml`](./dbt_project.yml) — project routing and tags.
- [`models/sources.yml`](./models/sources.yml) — Snowflake sources catalog.
- [`models/models.yml`](./models/models.yml) — transform + publish model
  documentation and tests.
