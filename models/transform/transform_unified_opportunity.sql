WITH edh_opps AS (

    SELECT
        edh_opp.opportunity_number,
        'EDH_SFDC'                                                      AS source_system,
        edh_opp.source_record_id                                        AS opportunity_id,
        edh_opp.opportunity_name,
        edh_opp.opportunity_stage                                       AS raw_stage,
        CASE
            WHEN edh_opp.opportunity_stage IN (
                '0-Closed/Lost', 'Closed/Lost', 'Closed', 'Closed Lost', '--None--'
            ) THEN 'Closed/Lost'
            WHEN edh_opp.opportunity_stage IN ('Won', '5-Closed/Won') THEN 'Won'
            WHEN edh_opp.opportunity_stage IN ('Stage 1', 'Stage1', '1-Prospecting') THEN 'Stage 1'
            WHEN edh_opp.opportunity_stage IN ('Stage 2', 'Stage2', '2-Qualifying') THEN 'Stage 2'
            WHEN edh_opp.opportunity_stage IN ('Stage 3', 'Stage3', '3-Solution Building') THEN 'Stage 3'
            WHEN edh_opp.opportunity_stage IN ('Stage 4', '4-Proposal/Negotiation') THEN 'Stage 4'
            WHEN edh_opp.opportunity_stage = 'Stage 5' THEN 'Stage 5'
            ELSE edh_opp.opportunity_stage
        END                                                             AS opportunity_stage,
        CASE
            WHEN edh_opp.opportunity_stage IN ('Stage 1', 'Stage1', '1-Prospecting') THEN 1
            WHEN edh_opp.opportunity_stage IN ('Stage 2', 'Stage2', '2-Qualifying') THEN 2
            WHEN edh_opp.opportunity_stage IN ('Stage 3', 'Stage3', '3-Solution Building') THEN 3
            WHEN edh_opp.opportunity_stage IN ('Stage 4', '4-Proposal/Negotiation') THEN 4
            WHEN edh_opp.opportunity_stage = 'Stage 5' THEN 5
            WHEN edh_opp.opportunity_stage IN ('Won', '5-Closed/Won') THEN 6
            ELSE 0
        END                                                             AS opportunity_stage_rank,
        CASE
            WHEN edh_opp.opportunity_stage IN ('Stage 1', 'Stage1', '1-Prospecting') THEN 0.10
            WHEN edh_opp.opportunity_stage IN ('Stage 2', 'Stage2', '2-Qualifying') THEN 0.20
            WHEN edh_opp.opportunity_stage IN ('Stage 3', 'Stage3', '3-Solution Building') THEN 0.30
            WHEN edh_opp.opportunity_stage IN ('Stage 4', '4-Proposal/Negotiation') THEN 0.50
            WHEN edh_opp.opportunity_stage = 'Stage 5' THEN 0.80
            WHEN edh_opp.opportunity_stage IN ('Won', '5-Closed/Won') THEN 1.00
            ELSE 0.00
        END                                                             AS opportunity_stage_weight,
        edh_opp.opportunity_type,
        edh_opp.primary_sales_motion,
        edh_opp.opportunity_forecast_category                           AS forecast_category,
        edh_opp.sales_channel,
        edh_opp.customer_project,
        edh_opp.compelling_event,
        edh_opp.access_to_funds,
        edh_opp.formal_decision_process,
        edh_opp.informal_decision_process,
        edh_opp.unique_business_value,
        bsd_opp.opportunity_tags__c                                     AS opportunity_tags,
        CASE
            WHEN LOWER(bsd_opp.opportunity_tags__c) LIKE '%partner led%'
              OR LOWER(bsd_opp.opportunity_tags__c) LIKE '%led by partner%'
                THEN 'Yes'
            ELSE 'No'
        END                                                             AS is_partner_led,
        CAST(edh_opp.source_created_ts AS DATE)                          AS opportunity_created_date,
        CAST(edh_opp.projected_close_date AS DATE)                      AS opportunity_projected_close_date,
        edh_opp.sales_rep_number                                        AS opportunity_owner_id
    FROM {{ source('edh_shared', 'opportunity') }} AS edh_opp
    LEFT JOIN {{ source('sfdc_shared', 'opportunity') }} AS bsd_opp
        ON edh_opp.source_record_id = bsd_opp.id
    WHERE edh_opp.opportunity_type = 'UnifiedOpportunity'
      AND edh_opp.opportunity_number IS NOT NULL

),

acs_only_opps AS (

    SELECT
        acs_opp.opportunity_number__c                                   AS opportunity_number,
        'ACS_SFDC'                                                      AS source_system,
        acs_opp.id                                                      AS opportunity_id,
        acs_opp.name                                                    AS opportunity_name,
        acs_opp.stage_name                                              AS raw_stage,
        CASE
            WHEN acs_opp.stage_name IN (
                '0-Closed/Lost', 'Closed/Lost', 'Closed', 'Closed Lost', '--None--'
            ) THEN 'Closed/Lost'
            WHEN acs_opp.stage_name IN (
                'Won', '5-Closed/Won', 'Booked', 'Closed Won', 'Console Add-On'
            ) THEN 'Won'
            WHEN acs_opp.stage_name IN ('Stage 1', 'Stage1', '1-Prospecting') THEN 'Stage 1'
            WHEN acs_opp.stage_name IN ('Stage 2', 'Stage2', '2-Qualifying') THEN 'Stage 2'
            WHEN acs_opp.stage_name IN ('Stage 3', 'Stage3', '3-Solution Building') THEN 'Stage 3'
            WHEN acs_opp.stage_name IN ('Stage 4', '4-Proposal/Negotiation') THEN 'Stage 4'
            WHEN acs_opp.stage_name = 'Stage 5' THEN 'Stage 5'
            ELSE acs_opp.stage_name
        END                                                             AS opportunity_stage,
        CASE
            WHEN acs_opp.stage_name IN ('Stage 1', 'Stage1', '1-Prospecting') THEN 1
            WHEN acs_opp.stage_name IN ('Stage 2', 'Stage2', '2-Qualifying') THEN 2
            WHEN acs_opp.stage_name IN ('Stage 3', 'Stage3', '3-Solution Building') THEN 3
            WHEN acs_opp.stage_name IN ('Stage 4', '4-Proposal/Negotiation') THEN 4
            WHEN acs_opp.stage_name = 'Stage 5' THEN 5
            WHEN acs_opp.stage_name IN (
                'Won', '5-Closed/Won', 'Booked', 'Closed Won', 'Console Add-On'
            ) THEN 6
            ELSE 0
        END                                                             AS opportunity_stage_rank,
        CASE
            WHEN acs_opp.stage_name IN ('Stage 1', 'Stage1', '1-Prospecting') THEN 0.10
            WHEN acs_opp.stage_name IN ('Stage 2', 'Stage2', '2-Qualifying') THEN 0.20
            WHEN acs_opp.stage_name IN ('Stage 3', 'Stage3', '3-Solution Building') THEN 0.30
            WHEN acs_opp.stage_name IN ('Stage 4', '4-Proposal/Negotiation') THEN 0.50
            WHEN acs_opp.stage_name = 'Stage 5' THEN 0.80
            WHEN acs_opp.stage_name IN (
                'Won', '5-Closed/Won', 'Booked', 'Closed Won', 'Console Add-On'
            ) THEN 1.00
            ELSE 0.00
        END                                                             AS opportunity_stage_weight,
        acs_opp.type                                                    AS opportunity_type,
        'NIL_ACS_SFDC'                                                  AS primary_sales_motion,
        'NIL_ACS_SFDC'                                                  AS forecast_category,
        acs_opp.bmtchannel_c                                            AS sales_channel,
        'NIL_ACS_SFDC'                                                  AS customer_project,
        'NIL_ACS_SFDC'                                                  AS compelling_event,
        'NIL_ACS_SFDC'                                                  AS access_to_funds,
        'NIL_ACS_SFDC'                                                  AS formal_decision_process,
        'NIL_ACS_SFDC'                                                  AS informal_decision_process,
        'NIL_ACS_SFDC'                                                  AS unique_business_value,
        'NIL_ACS_SFDC'                                                  AS opportunity_tags,
        'NIL_ACS_SFDC'                                                  AS is_partner_led,
        CAST(acs_opp.created_date AS DATE)                              AS opportunity_created_date,
        CAST(acs_opp.close_date AS DATE)                                AS opportunity_projected_close_date,
        acs_opp.owner_id                                                AS opportunity_owner_id
    FROM {{ source('dw_salesforce', 'dim_salesforce_opportunities') }} AS acs_opp
    LEFT JOIN {{ source('edh_shared', 'opportunity') }} AS edh_opp
        ON acs_opp.opportunity_number__c = edh_opp.opportunity_number
    WHERE acs_opp.opportunity_number__c IS NOT NULL
      AND edh_opp.opportunity_number IS NULL

)

SELECT * FROM edh_opps
UNION ALL
SELECT * FROM acs_only_opps
