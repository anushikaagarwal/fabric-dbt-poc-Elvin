{{ config(materialized='view') }}
-- Opt out of ephemeral default: MetricFlow requires a physical relation for
-- the time spine (see conventions.md §1.3). View is cheapest on Snowflake.
SELECT DATEADD(day, SEQ4(), '2015-01-01'::DATE) AS date_day
FROM TABLE(GENERATOR(ROWCOUNT => 9132))  -- 2015-01-01 through 2040-01-01
