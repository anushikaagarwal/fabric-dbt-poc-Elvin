WITH edh_accounts AS (
    SELECT
        acc.ACCOUNT_CSN                                                 AS account_csn,
        acc.ACCOUNT_NAME                                                AS account_name,
        acc.SALES_GEO                                                   AS account_geo,
        acc.COUNTRY_NAME                                                AS account_country,
        acc.SALES_REGION_NAME                                           AS account_region,
        acc.NAMED_ACCOUNT_GROUP                                         AS named_account_group,
        CASE
            WHEN acc.NAMED_ACCOUNT_GROUP IN ('Territory', 'Individual', 'Unknown') THEN 'Territory'
            ELSE acc.NAMED_ACCOUNT_GROUP
        END                                                             AS account_segment,
        acc.ACCOUNT_TYPE                                                AS account_type,
        acc.CORPORATE_ACCOUNT_NAME                                      AS parent_account_name,
        TRY_CAST(acc.ACCOUNT_HIERARCHY_DEPTH AS DECIMAL(18, 0))         AS account_hierarchy_depth,
        CAST(acc.ACCOUNT_HIERARCHY_LEVEL AS VARCHAR(255))             AS account_hierarchy_level,
        acc.ACCOUNT_CATEGORY                                            AS account_category,
        acc.INDUSTRY_SEGMENT                                            AS industry_segment,
        CASE UPPER(LTRIM(RTRIM(CAST(acc.IS_TARGETED_ACCOUNT AS VARCHAR(50)))))
            WHEN '1' THEN CAST(1 AS BIT)
            WHEN 'Y' THEN CAST(1 AS BIT)
            WHEN 'YES' THEN CAST(1 AS BIT)
            WHEN 'TRUE' THEN CAST(1 AS BIT)
            WHEN '0' THEN CAST(0 AS BIT)
            WHEN 'N' THEN CAST(0 AS BIT)
            WHEN 'NO' THEN CAST(0 AS BIT)
            WHEN 'FALSE' THEN CAST(0 AS BIT)
            ELSE NULL
        END                                                             AS is_targeted_account,
        CAST(acc.SALES_REP_NUMBER AS VARCHAR(255))                      AS account_sales_rep_number,
        'EDH'                                                           AS source_system
    FROM {{ source('edh_shared', 'account_ced') }} AS acc
    WHERE acc.ACCOUNT_CSN IS NOT NULL
),

acs_only_accounts AS (
    SELECT
        ca.AUTODESK_CSN                                                 AS account_csn,
        ca.ACCOUNT_NAME                                                 AS account_name,
        ca.GEO_C                                                        AS account_geo,
        ca.ACCOUNT_COUNTRY_C                                            AS account_country,
        CAST(NULL AS VARCHAR(255))                                      AS account_region,
        CAST(NULL AS VARCHAR(255))                                      AS named_account_group,
        CAST(NULL AS VARCHAR(255))                                      AS account_segment,
        ca.ACCOUNT_TYPE                                                 AS account_type,
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
        ON ca.AUTODESK_CSN = edh.ACCOUNT_CSN
    WHERE ca.AUTODESK_CSN IS NOT NULL
      AND edh.ACCOUNT_CSN IS NULL
)

SELECT * FROM edh_accounts
UNION ALL
SELECT * FROM acs_only_accounts
