{#
  Fabric Warehouse model routing for the sales semantic POC.
  Sources omit database in sources.yml and inherit target.database at parse time.
#}
{% macro generate_database_name(custom_database_name, node) -%}

    {%- if custom_database_name is none -%}
        {{ target.database }}
    {%- else -%}
        {{ custom_database_name | trim }}
    {%- endif -%}

{%- endmacro %}
