SELECT
    date_key                                                            AS date_day,
    fiscal_year_name,
    fiscal_year_quarter_name,
    month_number_in_fiscal_quarter,
    fiscal_year_name || '-' || fiscal_year_quarter_name                 AS fiscal_quarter,
    fiscal_year_name || '-' || fiscal_year_quarter_name
        || '-M' || CAST(month_number_in_fiscal_quarter AS INT)          AS fiscal_quarter_month
FROM {{ source('edh_shared', 'finance_calendar') }}
