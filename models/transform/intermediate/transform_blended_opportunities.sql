WITH quote_ranked AS (
    SELECT
        opportunity_number,
        quote_number,
        sales_partner_account_csn,
        quote_status,
        quote_date,
        ROW_NUMBER() OVER (
            PARTITION BY opportunity_number
            ORDER BY
                CASE WHEN quote_date IS NULL THEN 1 ELSE 0 END,
                quote_date DESC,
                quote_number DESC
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
        edh_opp.opportunity_number,
        edh_line.line_item_number,
        edh_opp.end_customer_account_csn                                AS account_csn,
        edh_opp.sales_partner_account_csn                               AS partner_csn,
        edh_opp.sales_partner_account_csn                               AS opportunity_partner_account_csn,
        edh_opp.sales_rep_number                                        AS opportunity_owner_id,
        acct.account_sales_rep_number                                   AS account_owner_id,
        CAST(edh_opp.projected_close_date AS DATE)                      AS opportunity_projected_close_date,
        edh_line.quantity,
        edh_line.line_item_acv_usd,
        edh_line.line_item_acv_usd
            * CASE
                WHEN edh_opp.opportunity_stage IN ('Stage 1', 'Stage1', '1-Prospecting') THEN 0.10
                WHEN edh_opp.opportunity_stage IN ('Stage 2', 'Stage2', '2-Qualifying') THEN 0.20
                WHEN edh_opp.opportunity_stage IN ('Stage 3', 'Stage3', '3-Solution Building') THEN 0.30
                WHEN edh_opp.opportunity_stage IN ('Stage 4', '4-Proposal/Negotiation') THEN 0.50
                WHEN edh_opp.opportunity_stage = 'Stage 5' THEN 0.80
                WHEN edh_opp.opportunity_stage IN ('Won', '5-Closed/Won') THEN 1.00
                ELSE 0.00
            END                                                         AS line_item_weighted_acv_usd,
        edh_line.sales_revenue_group_detail                             AS offer_type,
        edh_line.opportunity_line_status,
        edh_line.sales_motion_category,
        edh_line.action,
        edh_line.access_model                                           AS license_type,
        edh_line.term,
        offering.sales_motion_product_category,
        offering.offering_name,
        offering.solution_division,
        offering.focus_segment_group,
        offering.focus_segment,
        quote.quote_number,
        quote.sales_partner_account_csn                                 AS quote_partner_account_csn,
        quote.quote_status,
        quote.quote_date                                                AS quoted_on_date
    FROM {{ source('edh_shared', 'opportunity') }} AS edh_opp
    LEFT JOIN {{ source('edh_shared', 'opportunity_line_item') }} AS edh_line
        ON edh_opp.opportunity_number = edh_line.opportunity_number
    LEFT JOIN {{ source('edh_shared', 'offering') }} AS offering
        ON edh_line.offering_id = offering.offering_id
    INNER JOIN {{ source('edh_shared', 'account_ced') }} AS acct
        ON edh_opp.end_customer_account_csn = acct.account_csn
    LEFT JOIN quote_dedup AS quote
        ON quote.opportunity_number = edh_opp.opportunity_number
    WHERE acct.account_type IN ('End Customer', 'Strategic Account', 'Government', 'A.D.N.')
      AND acct.is_visible = 1
      AND COALESCE(acct.account_category, '') NOT IN ('Internal', 'Partner')
      AND CAST(edh_opp.projected_close_date AS DATE)
          BETWEEN CAST('2026-02-01' AS DATE) AND CAST('2028-01-31' AS DATE)
      AND edh_opp.opportunity_type = 'UnifiedOpportunity'

),

fx_rate_ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY from_currency_code
            ORDER BY effective_start_date DESC
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
        acs_opp.opportunity_number__c                                   AS opportunity_number,
        acs_line.id                                                     AS line_item_number,
        cust_acct.account_csn                                           AS account_csn,
        acs_acct.autodesk_child_account_csn                             AS partner_csn,
        acs_acct.autodesk_child_account_csn                             AS opportunity_partner_account_csn,
        acs_opp.owner_id                                                AS opportunity_owner_id,
        cust_acct.account_sales_rep_number                              AS account_owner_id,
        CAST(acs_opp.close_date AS DATE)                                AS opportunity_projected_close_date,
        acs_line.quantity,
        acs_line.est_annualized_amount_c * fx_rate.exchange_rate        AS line_item_acv_usd,
        (acs_line.est_annualized_amount_c * fx_rate.exchange_rate)
            * CASE
                WHEN acs_opp.stage_name IN ('Stage 1', 'Stage1', '1-Prospecting') THEN 0.10
                WHEN acs_opp.stage_name IN ('Stage 2', 'Stage2', '2-Qualifying') THEN 0.20
                WHEN acs_opp.stage_name IN ('Stage 3', 'Stage3', '3-Solution Building') THEN 0.30
                WHEN acs_opp.stage_name IN ('Stage 4', '4-Proposal/Negotiation') THEN 0.50
                WHEN acs_opp.stage_name = 'Stage 5' THEN 0.80
                WHEN acs_opp.stage_name IN (
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
        acs_line.subscription_name                                      AS offering_name,
        'NIL_ACS_SFDC'                                                  AS solution_division,
        'Emerging Tech'                                                 AS focus_segment_group,
        'Construction'                                                  AS focus_segment,
        'NIL_ACS_SFDC'                                                  AS quote_number,
        'NIL_ACS_SFDC'                                                  AS quote_partner_account_csn,
        'NIL_ACS_SFDC'                                                  AS quote_status,
        CAST(NULL AS DATE)                                              AS quoted_on_date
    FROM {{ source('dw_salesforce', 'dim_salesforce_opportunities') }} AS acs_opp
    LEFT JOIN {{ source('dw_salesforce', 'dim_salesforce_sales_opportunity_line_items') }} AS acs_line
        ON acs_opp.id = acs_line.opportunity_id
        AND acs_line.is_deleted = 0
    INNER JOIN {{ source('dw_salesforce', 'dim_salesforce_accounts') }} AS acs_acct
        ON acs_opp.account_id = acs_acct.account_id
    INNER JOIN {{ source('edh_shared', 'account_ced') }} AS cust_acct
        ON TRIM(acs_acct.autodesk_child_account_csn) = TRIM(cust_acct.account_csn)
    LEFT JOIN fx_rate
        ON acs_line.currency_iso_code = fx_rate.from_currency_code
    LEFT JOIN {{ source('edh_shared', 'opportunity') }} AS edh_opp
        ON acs_opp.opportunity_number__c = edh_opp.opportunity_number
    LEFT JOIN {{ source('dw_revops', 'stg_revops_country_region_map') }} AS geo
        ON LOWER(COALESCE(acs_opp.shipping_country, acs_acct.shipping_country)) = LOWER(geo.country)
    WHERE edh_opp.opportunity_number IS NULL
      AND NOT (geo.country IS NOT NULL AND acs_opp.is_closed = 0)
      AND COALESCE(acs_opp.reason_lost_c, 'n/a') <> 'Migrated to ENT'
      AND cust_acct.account_type IN ('End Customer', 'Strategic Account', 'Government', 'A.D.N.')
      AND cust_acct.is_visible = 1
      AND COALESCE(cust_acct.account_category, '') NOT IN ('Internal', 'Partner')
      AND CAST(acs_opp.close_date AS DATE)
          BETWEEN CAST('2026-02-01' AS DATE) AND CAST('2028-01-31' AS DATE)

)

SELECT * FROM edh_opps
UNION ALL
SELECT * FROM acs_opps
