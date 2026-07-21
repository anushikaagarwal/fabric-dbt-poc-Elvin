# tests/

Singular tests (raw SQL) and custom generic tests for the
`sales_semantic_models` project.

## Guidelines for singular tests

1. Tests must return **zero rows** on success. Any returned row = failure.
2. Only reference other models via `ref('...')` or declared sources via
   `source('...', '...')` - never hard-code database.schema.table paths.
3. Do **not** duplicate tests that are already defined under `models/models.yml`
   (`unique`, `not_null`, `accepted_values`, `relationships`, ...).
4. File naming convention:

   `<enterprise_dataset_name>_<test_name>_test.sql`

   for example `sales_opportunity_stage_valid_values_test.sql`.

5. Failures are persisted to `eio_ingest.sales_test_log` (configured via
   `tests: +schema` in `../dbt_project.yml`), so tests can be triaged after
   the fact.

## Sub-folders

Group tests into sub-folders when helpful, so `dbt test --select ...` can
target them:

- `generic/` - custom generic tests (`{% test %}` macros) reused across
  multiple models.
- `coverage_test/` - row-count / coverage checks between transform and
  publish layers.
- `freshness/` - custom freshness checks beyond `dbt source freshness`.

See the reference conventions in
`dags/dbt/dbt_template/project_folder/tests/README.md`.
