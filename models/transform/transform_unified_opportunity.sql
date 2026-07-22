WITH edh_opps AS (

    SELECT
        edh_opp.OPPORTUNITY_NUMBER                                      AS opportunity_number,
        'EDH_SFDC'                                                      AS source_system,
        edh_opp.SOURCE_RECORD_ID                                        AS opportunity_id,
        edh_opp.OPPORTUNITY_NAME                                        AS opportunity_name,
        edh_opp.OPPORTUNITY_STAGE                                       AS raw_stage,
        CASE
            WHEN edh_opp.OPPORTUNITY_STAGE IN (
                '0-Closed/Lost', 'Closed/Lost', 'Closed', 'Closed Lost', '--None--'
            ) THEN 'Closed/Lost'
            WHEN edh_opp.OPPORTUNITY_STAGE IN ('Won', '5-Closed/Won') THEN 'Won'
            WHEN edh_opp.OPPORTUNITY_STAGE IN ('Stage 1', 'Stage1', '1-Prospecting') THEN 'Stage 1'
            WHEN edh_opp.OPPORTUNITY_STAGE IN ('Stage 2', 'Stage2', '2-Qualifying') THEN 'Stage 2'
            WHEN edh_opp.OPPORTUNITY_STAGE IN ('Stage 3', 'Stage3', '3-Solution Building') THEN 'Stage 3'
            WHEN edh_opp.OPPORTUNITY_STAGE IN ('Stage 4', '4-Proposal/Negotiation') THEN 'Stage 4'
            WHEN edh_opp.OPPORTUNITY_STAGE = 'Stage 5' THEN 'Stage 5'
            ELSE edh_opp.OPPORTUNITY_STAGE
        END                                                             AS opportunity_stage,
        CASE
            WHEN edh_opp.OPPORTUNITY_STAGE IN ('Stage 1', 'Stage1', '1-Prospecting') THEN 1
            WHEN edh_opp.OPPORTUNITY_STAGE IN ('Stage 2', 'Stage2', '2-Qualifying') THEN 2
            WHEN edh_opp.OPPORTUNITY_STAGE IN ('Stage 3', 'Stage3', '3-Solution Building') THEN 3
            WHEN edh_opp.OPPORTUNITY_STAGE IN ('Stage 4', '4-Proposal/Negotiation') THEN 4
            WHEN edh_opp.OPPORTUNITY_STAGE = 'Stage 5' THEN 5
            WHEN edh_opp.OPPORTUNITY_STAGE IN ('Won', '5-Closed/Won') THEN 6
            ELSE 0
        END                                                             AS opportunity_stage_rank,
        CASE
            WHEN edh_opp.OPPORTUNITY_STAGE IN ('Stage 1', 'Stage1', '1-Prospecting') THEN 0.10
            WHEN edh_opp.OPPORTUNITY_STAGE IN ('Stage 2', 'Stage2', '2-Qualifying') THEN 0.20
            WHEN edh_opp.OPPORTUNITY_STAGE IN ('Stage 3', 'Stage3', '3-Solution Building') THEN 0.30
            WHEN edh_opp.OPPORTUNITY_STAGE IN ('Stage 4', '4-Proposal/Negotiation') THEN 0.50
            WHEN edh_opp.OPPORTUNITY_STAGE = 'Stage 5' THEN 0.80
            WHEN edh_opp.OPPORTUNITY_STAGE IN ('Won', '5-Closed/Won') THEN 1.00
            ELSE 0.00
        END                                                             AS opportunity_stage_weight,
        edh_opp.OPPORTUNITY_TYPE                                        AS opportunity_type,
        edh_opp.PRIMARY_SALES_MOTION                                    AS primary_sales_motion,
        edh_opp.OPPORTUNITY_FORECAST_CATEGORY                           AS forecast_category,
        edh_opp.SALES_CHANNEL                                           AS sales_channel,
        edh_opp.CUSTOMER_PROJECT                                        AS customer_project,
        edh_opp.COMPELLING_EVENT                                        AS compelling_event,
        edh_opp.ACCESS_TO_FUNDS                                         AS access_to_funds,
        edh_opp.FORMAL_DECISION_PROCESS                                 AS formal_decision_process,
        edh_opp.INFORMAL_DECISION_PROCESS                               AS informal_decision_process,
        edh_opp.UNIQUE_BUSINESS_VALUE                                   AS unique_business_value,
        bsd_opp.OPPORTUNITY_TAGS__C                                     AS opportunity_tags,
        CASE
            WHEN LOWER(bsd_opp.OPPORTUNITY_TAGS__C) LIKE '%partner led%'
              OR LOWER(bsd_opp.OPPORTUNITY_TAGS__C) LIKE '%led by partner%'
                THEN 'Yes'
            ELSE 'No'
        END                                                             AS is_partner_led,
        CAST(edh_opp.SOURCE_CREATED_TS AS DATE)                         AS opportunity_created_date,
        CAST(edh_opp.PROJECTED_CLOSE_DATE AS DATE)                      AS opportunity_projected_close_date,
        edh_opp.SALES_REP_NUMBER                                        AS opportunity_owner_id
    FROM {{ source('edh_shared', 'opportunity') }} AS edh_opp
    LEFT JOIN {{ source('sfdc_shared', 'opportunity') }} AS bsd_opp
        ON edh_opp.SOURCE_RECORD_ID = bsd_opp.ID
    WHERE edh_opp.OPPORTUNITY_TYPE = 'UnifiedOpportunity'
      AND edh_opp.OPPORTUNITY_NUMBER IS NOT NULL

),

acs_only_opps AS (

    SELECT
        acs_opp.OPPORTUNITY_NUMBER__C                                   AS opportunity_number,
        'ACS_SFDC'                                                      AS source_system,
        acs_opp.ID                                                      AS opportunity_id,
        acs_opp.NAME                                                    AS opportunity_name,
        acs_opp.STAGE_NAME                                              AS raw_stage,
        CASE
            WHEN acs_opp.STAGE_NAME IN (
                '0-Closed/Lost', 'Closed/Lost', 'Closed', 'Closed Lost', '--None--'
            ) THEN 'Closed/Lost'
            WHEN acs_opp.STAGE_NAME IN (
                'Won', '5-Closed/Won', 'Booked', 'Closed Won', 'Console Add-On'
            ) THEN 'Won'
            WHEN acs_opp.STAGE_NAME IN ('Stage 1', 'Stage1', '1-Prospecting') THEN 'Stage 1'
            WHEN acs_opp.STAGE_NAME IN ('Stage 2', 'Stage2', '2-Qualifying') THEN 'Stage 2'
            WHEN acs_opp.STAGE_NAME IN ('Stage 3', 'Stage3', '3-Solution Building') THEN 'Stage 3'
            WHEN acs_opp.STAGE_NAME IN ('Stage 4', '4-Proposal/Negotiation') THEN 'Stage 4'
            WHEN acs_opp.STAGE_NAME = 'Stage 5' THEN 'Stage 5'
            ELSE acs_opp.STAGE_NAME
        END                                                             AS opportunity_stage,
        CASE
            WHEN acs_opp.STAGE_NAME IN ('Stage 1', 'Stage1', '1-Prospecting') THEN 1
            WHEN acs_opp.STAGE_NAME IN ('Stage 2', 'Stage2', '2-Qualifying') THEN 2
            WHEN acs_opp.STAGE_NAME IN ('Stage 3', 'Stage3', '3-Solution Building') THEN 3
            WHEN acs_opp.STAGE_NAME IN ('Stage 4', '4-Proposal/Negotiation') THEN 4
            WHEN acs_opp.STAGE_NAME = 'Stage 5' THEN 5
            WHEN acs_opp.STAGE_NAME IN (
                'Won', '5-Closed/Won', 'Booked', 'Closed Won', 'Console Add-On'
            ) THEN 6
            ELSE 0
        END                                                             AS opportunity_stage_rank,
        CASE
            WHEN acs_opp.STAGE_NAME IN ('Stage 1', 'Stage1', '1-Prospecting') THEN 0.10
            WHEN acs_opp.STAGE_NAME IN ('Stage 2', 'Stage2', '2-Qualifying') THEN 0.20
            WHEN acs_opp.STAGE_NAME IN ('Stage 3', 'Stage3', '3-Solution Building') THEN 0.30
            WHEN acs_opp.STAGE_NAME IN ('Stage 4', '4-Proposal/Negotiation') THEN 0.50
            WHEN acs_opp.STAGE_NAME = 'Stage 5' THEN 0.80
            WHEN acs_opp.STAGE_NAME IN (
                'Won', '5-Closed/Won', 'Booked', 'Closed Won', 'Console Add-On'
            ) THEN 1.00
            ELSE 0.00
        END                                                             AS opportunity_stage_weight,
        acs_opp.TYPE                                                    AS opportunity_type,
        'NIL_ACS_SFDC'                                                  AS primary_sales_motion,
        'NIL_ACS_SFDC'                                                  AS forecast_category,
        acs_opp.BMTCHANNEL_C                                            AS sales_channel,
        'NIL_ACS_SFDC'                                                  AS customer_project,
        'NIL_ACS_SFDC'                                                  AS compelling_event,
        'NIL_ACS_SFDC'                                                  AS access_to_funds,
        'NIL_ACS_SFDC'                                                  AS formal_decision_process,
        'NIL_ACS_SFDC'                                                  AS informal_decision_process,
        'NIL_ACS_SFDC'                                                  AS unique_business_value,
        'NIL_ACS_SFDC'                                                  AS opportunity_tags,
        'NIL_ACS_SFDC'                                                  AS is_partner_led,
        CAST(acs_opp.CREATED_DATE AS DATE)                              AS opportunity_created_date,
        CAST(acs_opp.CLOSE_DATE AS DATE)                                AS opportunity_projected_close_date,
        acs_opp.OWNER_ID                                                AS opportunity_owner_id
    FROM {{ source('dw_salesforce', 'dim_salesforce_opportunities') }} AS acs_opp
    LEFT JOIN {{ source('edh_shared', 'opportunity') }} AS edh_opp
        ON acs_opp.OPPORTUNITY_NUMBER__C = edh_opp.OPPORTUNITY_NUMBER
    WHERE acs_opp.OPPORTUNITY_NUMBER__C IS NOT NULL
      AND edh_opp.OPPORTUNITY_NUMBER IS NULL

)

SELECT * FROM edh_opps
UNION ALL
SELECT * FROM acs_only_opps
