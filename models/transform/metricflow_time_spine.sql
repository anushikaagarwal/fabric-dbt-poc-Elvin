{{ config(materialized='view') }}
-- Opt out of ephemeral default: MetricFlow requires a physical relation for
-- the time spine. T-SQL date series for Fabric warehouse (2015-01-01 .. 2040-01-01).
WITH n AS (
    SELECT 0 AS n
    UNION ALL
    SELECT n + 1
    FROM n
    WHERE n < 9131
)
SELECT DATEADD(day, n, CAST('2015-01-01' AS DATE)) AS date_day
FROM n
OPTION (MAXRECURSION 9132)
