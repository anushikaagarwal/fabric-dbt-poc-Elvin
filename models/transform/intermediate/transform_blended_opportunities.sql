WITH quote_ranked AS (
    SELECT
        OPPORTUNITY_NUMBER                                              AS opportunity_number,
        QUOTE_NUMBER                                                    AS quote_number,
        SALES_PARTNER_ACCOUNT_CSN                                       AS sales_partner_account_csn,
        QUOTE_STATUS                                                    AS quote_status,
        QUOTE_DATE                                                      AS quote_date,
        ROW_NUMBER() OVER (
            PARTITION BY OPPORTUNITY_NUMBER
            ORDER BY
                CASE WHEN QUOTE_DATE IS NULL THEN 1 ELSE 0 END,
                QUOTE_DATE DESC,
                QUOTE_NUMBER DESC
        ) AS rn
    FROM {{ source('edh_shared', 'quote') }}
),

quote_dedup AS (
    SELECT
        opportunity_number,
        quote_number,
        sales_partner_account_csn,
        quote_status,
        quote_date
    FROM quote_ranked
    WHERE rn = 1
),

edh_opps AS (

    SELECT
        'EDH_SFDC'                                                      AS source_system,
        edh_opp.OPPORTUNITY_NUMBER                                      AS opportunity_number,
        edh_line.LINE_ITEM_NUMBER                                       AS line_item_number,
        edh_opp.END_CUSTOMER_ACCOUNT_CSN                                AS account_csn,
        edh_opp.SALES_PARTNER_ACCOUNT_CSN                               AS partner_csn,
        edh_opp.SALES_PARTNER_ACCOUNT_CSN                               AS opportunity_partner_account_csn,
        edh_opp.SALES_REP_NUMBER                                        AS opportunity_owner_id,
        acct.SALES_REP_NUMBER                                           AS account_owner_id,
        CAST(edh_opp.PROJECTED_CLOSE_DATE AS DATE)                      AS opportunity_projected_close_date,
        edh_line.QUANTITY                                               AS quantity,
        edh_line.LINE_ITEM_ACV_USD                                      AS line_item_acv_usd,
        edh_line.LINE_ITEM_ACV_USD
            * CASE
                WHEN edh_opp.OPPORTUNITY_STAGE IN ('Stage 1', 'Stage1', '1-Prospecting') THEN 0.10
                WHEN edh_opp.OPPORTUNITY_STAGE IN ('Stage 2', 'Stage2', '2-Qualifying') THEN 0.20
                WHEN edh_opp.OPPORTUNITY_STAGE IN ('Stage 3', 'Stage3', '3-Solution Building') THEN 0.30
                WHEN edh_opp.OPPORTUNITY_STAGE IN ('Stage 4', '4-Proposal/Negotiation') THEN 0.50
                WHEN edh_opp.OPPORTUNITY_STAGE = 'Stage 5' THEN 0.80
                WHEN edh_opp.OPPORTUNITY_STAGE IN ('Won', '5-Closed/Won') THEN 1.00
                ELSE 0.00
            END                                                         AS line_item_weighted_acv_usd,
        edh_line.SALES_REVENUE_GROUP_DETAIL                             AS offer_type,
        edh_line.OPPORTUNITY_LINE_STATUS                                AS opportunity_line_status,
        edh_line.SALES_MOTION_CATEGORY                                  AS sales_motion_category,
        edh_line.ACTION                                                 AS action,
        edh_line.ACCESS_MODEL                                           AS license_type,
        edh_line.TERM                                                   AS term,
        offering.SALES_MOTION_PRODUCT_CATEGORY                          AS sales_motion_product_category,
        offering.OFFERING_NAME                                          AS offering_name,
        offering.SOLUTION_DIVISION                                      AS solution_division,
        offering.FOCUS_SEGMENT_GROUP                                    AS focus_segment_group,
        offering.FOCUS_SEGMENT                                          AS focus_segment,
        quote.quote_number,
        quote.sales_partner_account_csn                                 AS quote_partner_account_csn,
        quote.quote_status,
        quote.quote_date                                                AS quoted_on_date
    FROM {{ source('edh_shared', 'opportunity') }} AS edh_opp
    LEFT JOIN {{ source('edh_shared', 'opportunity_line_item') }} AS edh_line
        ON edh_opp.OPPORTUNITY_NUMBER = edh_line.OPPORTUNITY_NUMBER
    LEFT JOIN {{ source('edh_shared', 'offering') }} AS offering
        ON edh_line.OFFERING_ID = offering.OFFERING_ID
    INNER JOIN {{ source('edh_shared', 'account_ced') }} AS acct
        ON edh_opp.END_CUSTOMER_ACCOUNT_CSN = acct.ACCOUNT_CSN
    LEFT JOIN quote_dedup AS quote
        ON quote.opportunity_number = edh_opp.OPPORTUNITY_NUMBER
    WHERE acct.ACCOUNT_TYPE IN ('End Customer', 'Strategic Account', 'Government', 'A.D.N.')
      AND acct.IS_VISIBLE = 1
      AND COALESCE(acct.ACCOUNT_CATEGORY, '') NOT IN ('Internal', 'Partner')
      AND CAST(edh_opp.PROJECTED_CLOSE_DATE AS DATE)
          BETWEEN CAST('2026-02-01' AS DATE) AND CAST('2028-01-31' AS DATE)
      AND edh_opp.OPPORTUNITY_TYPE = 'UnifiedOpportunity'

),

fx_rate_ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY FROM_CURRENCY_CODE
            ORDER BY EFFECTIVE_START_DATE DESC
        ) AS rn
    FROM {{ source('edh_shared', 'monthly_exchange_rate') }}
),

fx_rate AS (
    SELECT *
    FROM fx_rate_ranked
    WHERE rn = 1
),

acs_opps AS (

    SELECT
        'ACS_SFDC'                                                      AS source_system,
        acs_opp.OPPORTUNITY_NUMBER__C                                   AS opportunity_number,
        acs_line.ID                                                     AS line_item_number,
        cust_acct.ACCOUNT_CSN                                           AS account_csn,
        acs_acct.AUTODESK_CHILD_ACCOUNT_CSN                             AS partner_csn,
        acs_acct.AUTODESK_CHILD_ACCOUNT_CSN                             AS opportunity_partner_account_csn,
        acs_opp.OWNER_ID                                                AS opportunity_owner_id,
        cust_acct.SALES_REP_NUMBER                                      AS account_owner_id,
        CAST(acs_opp.CLOSE_DATE AS DATE)                                AS opportunity_projected_close_date,
        acs_line.QUANTITY                                               AS quantity,
        acs_line.EST_ANNUALIZED_AMOUNT_C * fx_rate.EXCHANGE_RATE        AS line_item_acv_usd,
        (acs_line.EST_ANNUALIZED_AMOUNT_C * fx_rate.EXCHANGE_RATE)
            * CASE
                WHEN acs_opp.STAGE_NAME IN ('Stage 1', 'Stage1', '1-Prospecting') THEN 0.10
                WHEN acs_opp.STAGE_NAME IN ('Stage 2', 'Stage2', '2-Qualifying') THEN 0.20
                WHEN acs_opp.STAGE_NAME IN ('Stage 3', 'Stage3', '3-Solution Building') THEN 0.30
                WHEN acs_opp.STAGE_NAME IN ('Stage 4', '4-Proposal/Negotiation') THEN 0.50
                WHEN acs_opp.STAGE_NAME = 'Stage 5' THEN 0.80
                WHEN acs_opp.STAGE_NAME IN (
                    'Won', '5-Closed/Won', 'Booked', 'Closed Won', 'Console Add-On'
                ) THEN 1.00
                ELSE 0.00
            END                                                         AS line_item_weighted_acv_usd,
        'NIL_ACS_SFDC'                                                  AS offer_type,
        'NIL_ACS_SFDC'                                                  AS opportunity_line_status,
        'NIL_ACS_SFDC'                                                  AS sales_motion_category,
        'NIL_ACS_SFDC'                                                  AS action,
        'NIL_ACS_SFDC'                                                  AS license_type,
        'NIL_ACS_SFDC'                                                  AS term,
        'NIL_ACS_SFDC'                                                  AS sales_motion_product_category,
        acs_line.SUBSCRIPTION_NAME                                      AS offering_name,
        'NIL_ACS_SFDC'                                                  AS solution_division,
        'Emerging Tech'                                                 AS focus_segment_group,
        'Construction'                                                  AS focus_segment,
        'NIL_ACS_SFDC'                                                  AS quote_number,
        'NIL_ACS_SFDC'                                                  AS quote_partner_account_csn,
        'NIL_ACS_SFDC'                                                  AS quote_status,
        CAST(NULL AS DATE)                                              AS quoted_on_date
    FROM {{ source('dw_salesforce', 'dim_salesforce_opportunities') }} AS acs_opp
    LEFT JOIN {{ source('dw_salesforce', 'dim_salesforce_sales_opportunity_line_items') }} AS acs_line
        ON acs_opp.ID = acs_line.OPPORTUNITY_ID
        AND acs_line.IS_DELETED = 0
    INNER JOIN {{ source('dw_salesforce', 'dim_salesforce_accounts') }} AS acs_acct
        ON acs_opp.ACCOUNT_ID = acs_acct.ACCOUNT_ID
    INNER JOIN {{ source('edh_shared', 'account_ced') }} AS cust_acct
        ON TRIM(acs_acct.AUTODESK_CHILD_ACCOUNT_CSN) = TRIM(cust_acct.ACCOUNT_CSN)
    LEFT JOIN fx_rate
        ON acs_line.CURRENCY_ISO_CODE = fx_rate.FROM_CURRENCY_CODE
    LEFT JOIN {{ source('edh_shared', 'opportunity') }} AS edh_opp
        ON acs_opp.OPPORTUNITY_NUMBER__C = edh_opp.OPPORTUNITY_NUMBER
    LEFT JOIN {{ source('dw_revops', 'stg_revops_country_region_map') }} AS geo
        ON LOWER(COALESCE(acs_opp.SHIPPING_COUNTRY, acs_acct.SHIPPING_COUNTRY)) = LOWER(geo.COUNTRY)
    WHERE edh_opp.OPPORTUNITY_NUMBER IS NULL
      AND NOT (geo.COUNTRY IS NOT NULL AND acs_opp.IS_CLOSED = 0)
      AND COALESCE(acs_opp.REASON_LOST_C, 'n/a') <> 'Migrated to ENT'
      AND cust_acct.ACCOUNT_TYPE IN ('End Customer', 'Strategic Account', 'Government', 'A.D.N.')
      AND cust_acct.IS_VISIBLE = 1
      AND COALESCE(cust_acct.ACCOUNT_CATEGORY, '') NOT IN ('Internal', 'Partner')
      AND CAST(acs_opp.CLOSE_DATE AS DATE)
          BETWEEN CAST('2026-02-01' AS DATE) AND CAST('2028-01-31' AS DATE)

)

SELECT * FROM edh_opps
UNION ALL
SELECT * FROM acs_opps
