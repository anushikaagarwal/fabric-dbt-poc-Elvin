{{ config(materialized='view') }}
-- Opt out of transform default: MetricFlow requires a physical relation for
-- the time spine. T-SQL date series for Fabric warehouse (2015-01-01 .. 2040-01-01).
-- Uses stacked cross joins; Fabric WH rejects recursive CTE + OPTION MAXRECURSION.
WITH digits AS (
    SELECT n
    FROM (VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9)) AS v(n)
),
l1 AS (
    SELECT 1 AS n
    FROM digits AS a
    CROSS JOIN digits AS b
),
l2 AS (
    SELECT 1 AS n
    FROM l1 AS a
    CROSS JOIN l1 AS b
),
l3 AS (
    SELECT 1 AS n
    FROM l2 AS a
    CROSS JOIN digits AS b
),
nums AS (
    SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
    FROM l3
)
SELECT DATEADD(day, n, CAST('2015-01-01' AS DATE)) AS date_day
FROM nums
WHERE n <= DATEDIFF(day, CAST('2015-01-01' AS DATE), CAST('2040-01-01' AS DATE))
