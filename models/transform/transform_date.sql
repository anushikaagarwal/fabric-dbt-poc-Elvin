-- Fabric WH: ingested columns are UPPERCASE and case-sensitive.
SELECT
    DATE_KEY                                                            AS date_day,
    FISCAL_YEAR_NAME                                                    AS fiscal_year_name,
    FISCAL_YEAR_QUARTER_NAME                                            AS fiscal_year_quarter_name,
    MONTH_NUMBER_IN_FISCAL_QUARTER                                      AS month_number_in_fiscal_quarter,
    FISCAL_YEAR_NAME || '-' || FISCAL_YEAR_QUARTER_NAME                 AS fiscal_quarter,
    FISCAL_YEAR_NAME || '-' || FISCAL_YEAR_QUARTER_NAME
        || '-M' || CAST(MONTH_NUMBER_IN_FISCAL_QUARTER AS INT)          AS fiscal_quarter_month
FROM {{ source('edh_shared', 'finance_calendar') }}
