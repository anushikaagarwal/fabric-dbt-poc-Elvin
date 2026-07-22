WITH edh_accounts AS (
    SELECT
        acc.account_csn,
        acc.account_name,
        acc.sales_geo                                                   AS account_geo,
        acc.country_name                                                AS account_country,
        acc.sales_region_name                                           AS account_region,
        acc.named_account_group,
        CASE
            WHEN acc.named_account_group IN ('Territory', 'Individual', 'Unknown') THEN 'Territory'
            ELSE acc.named_account_group
        END                                                             AS account_segment,
        acc.account_type,
        acc.corporate_account_name                                      AS parent_account_name,
        acc.account_hierarchy_depth,
        acc.account_hierarchy_level,
        acc.account_category,
        acc.industry_segment,
        acc.is_targeted_account,
        acc.sales_rep_number                                            AS account_sales_rep_number,
        'EDH'                                                           AS source_system
    FROM {{ source('edh_shared', 'account_ced') }} AS acc
    WHERE acc.account_csn IS NOT NULL
),

acs_only_accounts AS (
    SELECT
        ca.autodesk_csn                                                 AS account_csn,
        ca.account_name,
        ca.geo_c                                                        AS account_geo,
        ca.account_country_c                                            AS account_country,
        CAST(NULL AS VARCHAR(255))                                    AS account_region,
        CAST(NULL AS VARCHAR(255))                                      AS named_account_group,
        CAST(NULL AS VARCHAR(255))                                      AS account_segment,
        ca.account_type,
        CAST(NULL AS VARCHAR(255))                                      AS parent_account_name,
        CAST(NULL AS DECIMAL(18, 0))                                    AS account_hierarchy_depth,
        CAST(NULL AS VARCHAR(255))                                      AS account_hierarchy_level,
        CAST(NULL AS VARCHAR(255))                                      AS account_category,
        CAST(NULL AS VARCHAR(255))                                      AS industry_segment,
        CAST(NULL AS BIT)                                               AS is_targeted_account,
        CAST(NULL AS VARCHAR(255))                                      AS account_sales_rep_number,
        'ACS'                                                           AS source_system
    FROM {{ source('dw_salesforce', 'dim_salesforce_accounts') }} AS ca
    LEFT JOIN {{ source('edh_shared', 'account_ced') }} AS edh
        ON ca.autodesk_csn = edh.account_csn
    WHERE ca.autodesk_csn IS NOT NULL
      AND edh.account_csn IS NULL
)

SELECT * FROM edh_accounts
UNION ALL
SELECT * FROM acs_only_accounts
