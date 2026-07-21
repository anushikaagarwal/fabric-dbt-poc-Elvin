# macros/

Project-scoped Jinja macros for `sales_semantic_models`.

## Common routing macros

Database/schema/alias routing across `dev` and `prod` targets is provided
centrally by `dbt_common_packages/macros/`:

1. `generate_database_name.sql`
2. `generate_schema_name.sql`
3. `generate_alias_name.sql`

Those macros are already wired into this project via the `macro-paths`
entry in `../dbt_project.yml`:

```yaml
macro-paths:
  - "macros"
  - "{{ env_var('CLONED_PROJECT_PATH', '/usr/local/airflow') }}/dags/dbt/dbt_common_packages/macros"
```

Routing behaviour can be tuned via project vars (see `../dbt_project.yml`):

- `dev_database` - workspace database for `EIO_DI_GROUP` test/dev runs.
- `dev_schema` - workspace schema for `EIO_DI_GROUP` test/dev runs.
- `version_prefix` - alias prefix for test/dev versioned runs.

## Overriding a common macro

If this project ever needs custom routing, drop the corresponding file into
this folder (`generate_database_name.sql`, `generate_schema_name.sql`, or
`generate_alias_name.sql`) - dbt resolves project macros before those found
in `macro-paths`, so the local override wins.

Add any project-specific helper macros (Jinja functions for the semantic
layer, shared SQL snippets, etc.) here as well.
