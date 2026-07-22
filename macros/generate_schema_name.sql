{#
  Fabric POC: use custom +schema values as-is (sales_transform, sales_shared, etc.).
  Default dbt concatenates target.schema + custom schema, which produced
  sales_shared_sales_transform when the Fabric profile schema was sales_shared.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}

{%- endmacro %}
