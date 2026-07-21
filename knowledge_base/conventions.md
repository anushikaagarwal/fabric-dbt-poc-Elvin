# Conventions — sales_semantic_models

Analytics Engineering enablement guide for `sales_semantic_models`.
Documents how to translate analyst SQL into the layered dbt models that feed
Power BI and Looker with consistent, governed logic.

Read alongside [`AGENTS.md`](../AGENTS.md) at the project root.

- **Owner**: _TBD_
- **Last updated**: 2026-07-14

## POC scope notes

This project is a working POC. The rules below describe the team's target
conventions; a few items are intentionally deferred:

- **Materialization**: ephemeral is the project-wide default set in
  `dbt_project.yml` for `transform`, `publish/shared`, and `publish/private`.
  Individual models may opt out via `{{ config(materialized='...') }}` with
  a one-line justification (typical case: a mart that must materialize as
  `table` for BI Direct Lake).
- **Target warehouse** is Snowflake (`eio_ingest`, `eio_publish`). Fabric
  migration is out of scope for this POC.
- **`models/ingest/`** folder is not created yet. Sources are referenced
  directly in `models/transform/*.sql` via `{{ source(...) }}` IMPORT CTEs.
  When the ingest layer is introduced, transforms will refactor to
  `{{ ref('ingest_<name>') }}` (no downstream changes required).
- **Sensitivity split** (`publish/shared/` vs `publish/private/`) is retained.
  Note that if a model is ephemeral, sensitivity becomes organizational
  documentation only — enforcement requires a materialized downstream object.

## 1. Architecture overview

### 1.1 Data flow

```
Source systems  ->  Snowflake (eio_ingest, eio_publish, bsd_publish, ...)
             ->  dbt (transform -> publish -> metrics)
             ->  Power BI (DAX) and Looker (LookML)
```

Publish-layer models define the single source of truth for grain, joins, and
core business calculations. Power BI and Looker add only report-specific or
UI logic on top.

### 1.2 Delivery pattern

Two supported paths from dbt to the BI tools:

| Option | Description | When to use |
| --- | --- | --- |
| **A. Direct warehouse connection** | BI tools consume the governed compiled SQL from dbt models. Default approach. | Default. Fast, simple, no extra infrastructure. |
| **B. dbt Semantic Layer (MetricFlow)** | Metrics defined once in YAML, queried via CLI/API. | Strict KPI governance. Full hosted BI connectors require dbt Cloud; on dbt Core, MetricFlow is used for documentation, validation, and CLI-based queries. |

Primary delivery pattern: Option A. dbt Semantic Layer definitions in
`models/metrics/` remain the governance and documentation surface for metrics.

### 1.3 Time spine requirement for the semantic layer

MetricFlow requires a project-wide **time spine model** whenever any semantic
model declares time dimensions (all `sem_*.yml` files in this project do).
Without a spine, `dbt parse` fails hard on the semantic manifest with a
misleading error message that surfaces as a `PydanticSemanticModel`
`relation_name` validation error on the first semantic model it processes.

This project satisfies the requirement via:

- `models/transform/metricflow_time_spine.sql` — thin generator producing one
  row per day (2015-01-01 through 2040-01-01), materialized as a **view** to
  opt out of the project-wide ephemeral default. MetricFlow needs a physical
  relation to join to.
- `models/transform/metricflow_time_spine.yml` — declares the model as a time
  spine with `date_day` at day granularity.

The spine resolves the time-spine-granularity requirement, but it does
**not** resolve a separate, still-open issue: dbt-core sets
`relation_name = None` on every ephemeral model (by design — ephemeral
models have no physical relation), while MetricFlow's semantic manifest
requires a non-null `relation_name` on the model backing each
`semantic_models:` entry. Because `publish/shared` and `publish/private`
are ephemeral by default, **every** full manifest load (`dbt parse`,
`compile`, `build`, `run`, `test`, `ls` — with or without `--select`) fails
with:

```
1 validation error for PydanticSemanticModel
node_relation -> relation_name
  none is not an allowed value (type=type_error.none.not_allowed)
```

This reproduces on the project's own committed baseline models
(`fct_blended_opportunities` / `sem_blended_opportunities.yml`), so it is
not caused by any particular new model. It is a structural dbt-core /
MetricFlow limitation with ephemeral-by-default + semantic layer, not a bug
to chase per model. See `AGENTS.md`'s POC caveats. Until this is resolved
(e.g. by opting the specific publish models backing semantic models out of
ephemeral), do not run dbt CLI commands as a validation gate for new
transform/publish/semantic model sets.

**Do not delete `metricflow_time_spine.*`.** It is not a business dimension —
downstream transform / publish models must not `ref()` it or join to it.
It exists solely to satisfy MetricFlow's time-spine-granularity requirement
and to serve time-based metric queries (gap-free time series, cumulative
windows) at query time.

## 2. dbt project structure

### 2.1 Folder layout

```
models/
├── sources.yml                                    # sources: catalog (Snowflake source tables)
├── models.yml                                     # transform + publish model documentation and tests
├── transform/                                     # transform_*.sql — one per publish model
│   └── intermediate/                              # cross-source-system unions, dedup, re-graining (see §2.1a)
├── publish/
│   ├── shared/                                    # fct_*.sql / dim_*.sql — readonly-role accessible
│   │   └── fct_<name>.relationships.yml           # Fabric relationships sidecar (one per fact)
│   └── private/                                   # fct_*.sql / dim_*.sql — restricted access
│       └── fct_<name>.relationships.yml           # Fabric relationships sidecar (one per fact)
└── metrics/                                       # sem_*.yml — semantic models and metric definitions
analyses/                                          # ad-hoc SQL, never materialized (see §4)
macros/
seeds/
snapshots/
tests/
```

### 2.1a Why `transform/intermediate/` exists (and isn't a fact/dim split)

dbt's official [How we structure our dbt projects](https://docs.getdbt.com/best-practices/how-we-structure/1-guide-overview)
guide deliberately does **not** organize models by fact-vs-dimension —
that's a traditional Kimball star-schema idea the guide explicitly
departs from. Instead it differentiates by pipeline stage (staging →
intermediate → marts) and, within a stage, by business domain.

This project fuses staging + intermediate into one `transform/` layer
(see POC caveats in `AGENTS.md` — no `ingest/` layer yet). But some
transforms still do genuinely different work than the rest:

- **`transform/` root** — thin, source-conformed passthroughs: one
  source table, light renaming/casing, no re-graining. E.g.
  `transform_unified_account`, `transform_unified_contact`,
  `transform_unified_employee`, `transform_unified_opportunity`,
  `transform_date`.
- **`transform/intermediate/`** — cross-source-system unions,
  deduplication (`QUALIFY ROW_NUMBER()`), and re-graining (e.g. fanning
  out to line-item grain). This matches dbt's own definition of
  intermediate-layer work: *"structural simplification," "re-graining,"*
  and *"isolating complex operations."* E.g.
  `transform_blended_opportunities` (dedupes quotes, unions EDH + ACS,
  fans out to line-item grain) and
  `transform_blended_opportunity_activities` (unions EDH + Construction,
  applies multi-branch activity-taxonomy business rules).

The split is about **transformation complexity/grain**, not about
whether the model happens to back a `fct_*` or `dim_*` publish model.
A future dimension transform that has to union three source systems and
dedupe would belong in `intermediate/` too.

Both `sources.yml` and `models.yml` are standard dbt properties files
(`version: 2` at the top). Their split follows the sibling
`federated_workflow/coo_emerging_gtm/customer/emerging_core/` convention:
`sources.yml` contains **only** `sources:`; `models.yml` contains **only**
`models:`. dbt globs every `.yml` under `model-paths` — the filenames are
convention, not configuration.

Domain subfolders inside each layer (e.g. `transform/opportunities/`) are
deferred until the project spans multiple sales sub-domains.

### 2.2 Layer responsibilities

| Layer | Responsibility | Consumed by |
| --- | --- | --- |
| `transform/` | Joins, filters, reusable business logic. Wraps `{{ source(...) }}` at the top of each file until the ingest layer is added. | `publish/` only |
| `publish/shared/` | Analytics-ready `fct_*` / `dim_*` marts at business grain. Readonly-role accessible. | Power BI, Looker, downstream models, analyses |
| `publish/private/` | Same as shared, but restricted-access. | Restricted-role consumers |
| `metrics/` | Semantic models (entities, dimensions, measures) and metric definitions in YAML. | dbt Docs, MetricFlow CLI, downstream BI governance |
| `analyses/` | Version-controlled ad-hoc SQL; never materialized. | Analysts, one-off requests |

### 2.3 Naming and materialization

| Layer | File prefix | Default materialization |
| --- | --- | --- |
| `transform/` | `transform_*` | Ephemeral (project default) |
| `publish/shared/` | `fct_*` / `dim_*` | Ephemeral (project default) |
| `publish/private/` | `fct_*` / `dim_*` | Ephemeral (project default) |
| `metrics/` | `sem_*` | YAML only (no SQL, no materialization) |

Ephemeral is the project-wide default, set once in `dbt_project.yml`.
Individual models should not add `{{ config(materialized='ephemeral') }}`
— it is redundant. Where a model needs to opt OUT (e.g. materialize as
`table` for direct BI consumption), state the override in the model's
`{{ config(...) }}` block with a one-line comment on why.

### 2.4 STAR schema and conformed dimensions

Publish-layer facts follow a STAR schema:

- Every `fct_*` model is **narrow**: foreign keys, additive measures,
  and intrinsic degenerate dimensions (attributes that belong to the
  fact event itself and cannot be resolved via any dim).
- Every descriptive attribute that belongs to a business entity
  (account, employee, contact, opportunity, date, ...) lives on that
  entity's conformed **`dim_*`** model, not on the fact.
- Downstream consumers (BI, semantic layer, analyses) join the fact to
  the dim via the FK to resolve the descriptive attributes.

Conformed dims are shared across every fact that touches the same
entity. Current conformed dims:

- `dim_date` (shared)
- `dim_unified_account` (shared)
- `dim_unified_employee` (shared)
- `dim_unified_opportunity` (shared)
- `dim_unified_contact` (private — PII)

Before adding a new fact:

1. List every business entity the fact touches.
2. For each entity, decide **reuse** (dim already covers it) / **extend**
   (add a column to an existing dim) / **create** (no dim exists for
   the entity yet).
3. Only after that plan is set, build the fact narrow.

### 2.5 One transform per publish model

Every `fct_*.sql` and every `dim_*.sql` is backed by exactly one
`transform_<base>.sql` with the matching base name, regardless of
whether that file lives at `transform/` root or under
`transform/intermediate/` (see §2.1a). Never split a publish model into
multiple transforms; if the SQL feels too big for one transform, that is
a signal to offload descriptive attributes to a conformed dim, not to
fragment the fact's own logic.

A fact that requires three new dims produces four transform files (one
fact + three dims) and four publish files — but still one transform per
publish model.

### 2.6 Fabric relationships sidecar

Every `fct_*.sql` in `publish/{shared,private}/` has a sibling
`fct_<base>.relationships.yml` file. The sidecar documents the fact's
foreign keys in a Fabric-friendly shape:

```yaml
fact: fct_<base>
grain: one row per <grain>
relationships:
  - name: to_<dim>
    to_model: dim_<dim_base>
    from_column: <fk_col>
    to_column: <dim_pk>
    cardinality: many_to_one
    cross_filter_direction: single
    is_active: true            # false + role for role-playing duplicates
    role: <role_name>          # only for role-playing FKs
```

The same FKs are also enforced inside dbt via `relationships` tests
(severity `warn`) in `models/models.yml`. The sidecar is the Fabric
contract; the dbt test is the CI safety net.

### 2.7 Reuse-first governance

Before creating any new model, metric, fact, or dimension, review whether an
existing asset can be updated or extended. New files should only be created
when the requirement represents a genuinely new grain, entity, business
process, or KPI definition that cannot be safely incorporated into an
existing asset.

### 2.8 Publish-layer completeness

The publish layer must contain the full set of `fct_*` and `dim_*` models
required by Power BI and Looker consumption. Before enabling or changing a BI
use case:

- Confirm all required facts and dimensions exist under `publish/shared/` or
  `publish/private/`.
- Confirm each has a `description:` and appropriate tests in `models.yml`.
- Confirm each covers the required grain, keys, joins, and business
  attributes.

Where a required fact or dimension is missing, check whether an existing
publish model can be extended before creating a new one.

## 3. Documenting metrics and dimensions

Metrics and dimensions are documented in `models/metrics/*.yml` using dbt's
`semantic_models:` and `metrics:` YAML specification, built on top of the
publish layer.

### 3.1 File organization

- One YAML file per semantic model (i.e. per publish model), not one file
  per metric.
- Files live in `models/metrics/`, prefixed `sem_` and mirroring the publish
  model they describe.
- Example: `publish/shared/fct_orders.sql` -> `metrics/sem_orders.yml`.

### 3.2 Semantic model — entities, dimensions, measures

A semantic model documents the vocabulary of a publish model: its primary
and foreign keys (entities), slice-able attributes (dimensions), and
aggregatable columns (measures).

```yaml
# models/metrics/sem_orders.yml
semantic_models:
  - name: orders
    description: "One row per order, excludes cancelled orders."
    model: ref('fct_orders')
    defaults:
      agg_time_dimension: order_date
    entities:
      - name: order_id
        type: primary
      - name: customer_id
        type: foreign
    dimensions:
      - name: order_date
        type: time
        type_params:
          time_granularity: day
      - name: region
        type: categorical
    measures:
      - name: net_revenue
        description: "Sum of order revenue after discounts and refunds."
        agg: sum
        expr: net_revenue
      - name: order_count
        agg: sum
        expr: order_count_flag
```

### 3.3 Metrics

Every metric must include a `description` and `label`. These become the text
shown in dbt Docs and downstream tools.

```yaml
metrics:
  - name: revenue
    description: "Total net revenue across all completed orders."
    label: "Revenue"
    type: simple
    type_params:
      measure: net_revenue

  - name: average_order_value
    description: "Revenue / order count. Cancelled orders already excluded upstream."
    label: "Average Order Value"
    type: ratio
    type_params:
      numerator: revenue
      denominator: order_count
```

### 3.4 Dimension tables (`dim_*`)

Pure dimension tables still get a semantic model — kept minimal, with just
the primary entity and its dimensions. Avoid pre-joining every dimension
attribute into fact models; MetricFlow joins dynamically via shared
entities.

```yaml
# models/metrics/sem_customers.yml
semantic_models:
  - name: customers
    model: ref('dim_customers')
    entities:
      - name: customer_id
        type: primary
    dimensions:
      - name: customer_segment
        type: categorical
      - name: signup_date
        type: time
        type_params:
          time_granularity: day
```

### 3.5 Governance checklist

- Every metric has a business-meaning description, including exclusions
  (e.g. "excludes cancelled orders").
- Each metric domain has a named owner.
- Repeated business definitions use `doc()` blocks instead of retyping.
- Every Power BI report and Looker Explore consuming a publish model has a
  matching dbt `exposure`.
- CI fails (or warns) if a new model or metric is left undocumented.
- Naming collisions are disambiguated (e.g. `customers__region` vs
  `orders__region`).
- Before adding any new asset, reviewers confirm no existing asset can be
  extended instead.
- Publish-layer coverage is reviewed to confirm all required `fct_*` and
  `dim_*` assets are available and documented (see §2.8).

### 3.6 Local validation

```bash
dbt parse
dbt sl list metrics
dbt sl list dimensions --metrics revenue
dbt docs generate --target prod
dbt docs serve --port 8080 --no-browser
```

On dbt Core, treat `dbt sl` commands mainly as validation and documentation
tooling. Live metric querying via API typically requires dbt Cloud's
Semantic Layer access.

## 4. Ad-hoc analysis

For one-off questions, two supported paths.

### 4.1 `analyses/` folder

Use for investigations, audits, or custom filters and joins not covered by
existing metrics. Files compile via dbt but are never materialized.

```sql
-- analyses/q4_revenue_by_region_investigation.sql
select
    o.region,
    date_trunc('month', o.order_date) as order_month,
    sum(o.net_revenue) as total_revenue,
    sum(o.order_count_flag) as total_orders
from {{ ref('fct_orders') }} o
where o.order_date >= '2026-10-01'
group by 1, 2
order by 1, 2
```

Workflow: write SQL -> `dbt compile` -> run the compiled SQL (found under
`target/compiled/.../analyses/`) in Snowsight or the BI SQL editor.

### 4.2 MetricFlow CLI

Use when the question is answerable with existing, documented metrics and
dimensions. Guarantees the same logic as production dashboards.

```bash
dbt sl query --metrics revenue --group-by metric_time__month,region
dbt sl query --metrics order_count,revenue --group-by customer__customer_segment --order-by -revenue
```

### 4.3 Choosing the approach

| Scenario | Use |
| --- | --- |
| Revenue by region, last quarter | MetricFlow CLI (governed logic) |
| Custom filter or join not in existing metrics | `analyses/` SQL file |
| One-time audit comparing two tables | `analyses/` SQL file |
| Repeated stakeholder request | Promote to a documented metric or reusable ephemeral publish model |

### 4.4 Rules of thumb

- Always reference `ref('fct_...')` / `ref('dim_...')` — never hardcode
  schema names.
- Organize `analyses/` into subfolders by theme or requester as it grows.
- If a "one-off" query gets requested repeatedly, promote it into a
  reusable publish model or documented metric.

## 5. End-to-end workflow

| Step | Action | Owner |
| --- | --- | --- |
| 1 | Declare each upstream source in `models/sources.yml` (repo convention: source `name:` = Snowflake schema name). | Analytics Engineering |
| 2 | Build transform models under `models/transform/` — joins, filters, reusable logic. Wrap `{{ source(...) }}` at the top of each file. | Analytics Engineering |
| 3 | Build publish models under `publish/shared/` or `publish/private/` — final `fct_*` / `dim_*` at business grain. Reuse conformed dims wherever possible (see §2.4). Facts stay narrow (STAR schema). | Analytics Engineering |
| 4 | For every new fact, add a `fct_<name>.relationships.yml` sidecar in the same folder documenting its FKs (see §2.6). | Analytics Engineering |
| 5 | Document semantic models, dimensions, and metrics in `models/metrics/sem_*.yml`. | Analytics Engineering |
| 6 | Add dbt tests in `models/models.yml`: `unique` + `not_null` on every dim PK, `not_null` on every fact PK, `accepted_values` on `source_system` columns, and a `relationships` test (severity `warn`) on every fact FK. | Analytics Engineering |
| 7 | Run `dbt compile` / `dbt build`; validate tests and docs. | Analytics Engineering / CI |
| 8 | Build LookML views/Explores and Power BI semantic models on top of the publish layer. | BI Developers |
| 9 | Add a dbt `exposure` for every dashboard or Explore that consumes a publish model. | Dashboard Owner |
| 10 | Before adding new assets, verify no existing publish or semantic asset can be extended instead (see §2.7). Reuse conformed dims (see §2.4) before creating new ones. | Analytics Engineering / Governance |
| 11 | Confirm publish-layer completeness for the BI use cases (see §2.8). | Analytics Engineering / BI |
| 12 | Run parity checks between dbt, Power BI, and Looker outputs. | QA / Analytics Engineering |

## Key takeaway

dbt's `transform -> publish -> metrics` pipeline is the single source of
truth for grain, joins, and KPI logic. Power BI and Looker are presentation
layers that must consume the same governed logic. Documented metrics and
dimensions in `models/metrics/` are what let both tools — and every analyst
running ad-hoc queries — agree on the same numbers.

## Golden rule

Never define the same business rule (e.g. "exclude cancelled orders") in
more than one place across dbt, LookML, and DAX. If the transform or
publish layer already filters it, do not re-filter downstream. That is
how metric drift starts.

---

## Change log

| Date | Change | Author |
| --- | --- | --- |
| 2026-07-14 | Reformatted from team enablement doc into POC-scoped Markdown; trimmed LookML/DAX and Fabric sections; consolidated ephemeral-everywhere repetitions into POC scope notes. | _TBD_ |
| 2026-07-16 | Added §1.3 documenting the known `dbt parse` failure caused by ephemeral publish models backing semantic models (flag-only, no action required). | _TBD_ |
| 2026-07-17 | §1.3 rewritten: added `models/transform/metricflow_time_spine.{sql,yml}`, resolving the previously documented `dbt parse` failure. Ephemeral publish models now parse cleanly. | _TBD_ |
| 2026-07-21 | Split `models/schema.yml` into `models/sources.yml` (sources catalog) and `models/models.yml` (transform + publish model docs and tests), matching the sibling `emerging_core` convention. File contents moved verbatim — no logic or test changes. | _TBD_ |
| 2026-07-21 | Adopted STAR schema across the publish layer: introduced conformed dims (`dim_date`, `dim_unified_account`, `dim_unified_employee`, `dim_unified_opportunity`, `dim_unified_contact`); narrowed `fct_blended_opportunities` and `fct_blended_opportunity_activities` to FKs + measures + intrinsic degenerate dims. Added `fct_<name>.relationships.yml` sidecars for Fabric on every fact. Formalised the one-transform-per-publish-model rule and the conformed-dim reuse workflow (§2.4-2.6). | _TBD_ |
| 2026-07-21 | Added `models/transform/intermediate/` subfolder (§2.1a) for transforms that union multiple source systems, dedupe, or re-grain, following dbt's official staging vs. intermediate structure (not a fact/dim split). Moved and renamed `transform_unified_opportunities` → `transform/intermediate/transform_blended_opportunities` and `transform_unified_activities` → `transform/intermediate/transform_blended_opportunity_activities` to match their publish model names. | _TBD_ |
