# metrics/

dbt Semantic Layer definitions for the sales domain.

## What lives here

YAML files (`sem_<name>.yml`) that declare:

- `semantic_models:` — entities, dimensions, and measures anchored on a
  publish-layer mart via `model: ref('<mart>')`.
- `metrics:` — governed metric definitions derived from those measures
  (`simple` / `ratio` / `cumulative` / `derived`).
- `saved_queries:` — optional canonical query bundles for downstream
  consumers.

No SQL is materialized from this folder. dbt parses the YAML and exposes
the definitions through the Semantic Layer for BI and ad-hoc consumers.

## Naming

- One file per semantic model, prefixed `sem_` and mirroring the publish
  model it describes.
- Example: `publish/shared/fct_orders.sql` -> `metrics/sem_orders.yml`.
- The folder is flat — no `shared/private` split. Sensitivity is enforced
  at the underlying publish model, not here.

## Conventions

- Reference the publish mart via `ref(...)`, never `source(...)`.
- Declare a primary `entity` on every semantic model.
- Declare a time `dimension` with `type_params.time_granularity` on every
  semantic model that supports time slicing.
- Every metric must include a `label` and a `description`. Descriptions
  must state exclusions (e.g. "excludes cancelled orders").

See §3 of `../../knowledge_base/conventions.md` for the full playbook and
worked YAML templates.
