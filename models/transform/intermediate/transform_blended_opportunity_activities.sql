WITH activities_edh AS (
    SELECT
        t.task_id                                               AS activity_id,
        o.end_customer_account_csn                              AS account_csn,
        o.opportunity_number                                    AS opportunity_number,
        o.source_record_id                                      AS whatid,
        t.assigned_to_employee_number                           AS ownerid,
        t.end_customer_contact_csn                              AS account_contact_csn,
        t.subject_line                                          AS activity_subject,
        t.task_type,
        t.task_subtype,
        t.task_status,
        TO_DATE(t.source_created_ts)                            AS activity_created_date,
        t.source_created_ts                                     AS activity_created_timestamp,
        TO_DATE(t.task_activity_date)                           AS activity_date,
        t.task_completed_ts                                     AS activity_completed_timestamp,
        TRIM(t.sales_activity_subtype)                          AS cadence_activity_sub_type,
        TRIM(t.sales_activity_type)                             AS cadence_activity_type,
        NULL::VARCHAR                                           AS call_outcome,
        NULL::VARCHAR                                           AS call_type_raw,
        NULL::FLOAT                                             AS outreach_call_duration_seconds,
        CASE
            WHEN t.task_subtype = 'Task' AND NULLIF(TRIM(t.sales_activity_type), '') = 'Call' THEN 'Call'
            WHEN t.task_subtype = 'Call' AND NULLIF(TRIM(t.sales_activity_type), '') = 'Meeting' THEN 'Meeting'
            WHEN t.task_subtype = 'Task' AND NULLIF(TRIM(t.sales_activity_type), '') = 'Email' THEN 'Email'
            WHEN t.task_subtype = 'Task' AND NULLIF(TRIM(t.sales_activity_type), '') IS NULL
                 AND t.sales_activity_subtype = 'Email - Response Received' THEN 'Email'
            WHEN t.task_subtype = 'Task' AND NULLIF(TRIM(t.sales_activity_type), '') IS NULL
                 AND t.subject_line ILIKE '%Sub-Call%' THEN 'Call'
            WHEN t.task_subtype = 'Task' AND NULLIF(TRIM(t.sales_activity_type), '') IS NULL
                 AND t.subject_line ILIKE '%InMail%' THEN 'Email'
            WHEN t.task_subtype = 'Task' AND NULLIF(TRIM(t.sales_activity_type), '') IS NULL
                 AND t.task_description ILIKE '%EXTERNAL EMAIL%' THEN 'Email'
            WHEN t.task_subtype = 'Task' AND NULLIF(TRIM(t.sales_activity_type), '') IS NULL
                 AND t.task_description ILIKE '%Email sent successfully%' THEN 'Email'
            WHEN t.task_subtype = 'Task'
             AND NULLIF(TRIM(t.sales_activity_type), '') IN ('Chat', 'Meeting', 'Social', 'Update')
                THEN TRIM(t.sales_activity_type)
            WHEN NULLIF(TRIM(t.sales_activity_type), '') IN ('Call', 'Scheduled Call') THEN 'Call'
            WHEN NULLIF(TRIM(t.sales_activity_type), '') = 'Email' THEN 'Email'
            WHEN NULLIF(TRIM(t.sales_activity_type), '') = 'Meeting' THEN 'Meeting'
            WHEN NULLIF(TRIM(t.sales_activity_type), '') IN ('Chat', 'Social', 'Update') THEN TRIM(t.sales_activity_type)
            ELSE COALESCE(NULLIF(TRIM(t.task_subtype), ''), 'Task')
        END                                                     AS new_activity_type,
        CASE
            WHEN TRIM(t.sales_activity_subtype) = 'Email - Sent' THEN 'Outbound'
            WHEN TRIM(t.sales_activity_subtype) = 'Email - Response Received' THEN 'Inbound'
            WHEN TRIM(t.sales_activity_subtype) = 'Email - Engaged with Partner' THEN 'Outbound'
            WHEN NULLIF(TRIM(t.sales_activity_type), '') IN ('Call', 'Scheduled Call') OR t.task_subtype = 'Call' THEN 'Outbound'
            WHEN NULLIF(TRIM(t.sales_activity_type), '') = 'Email' AND t.task_type = 'Inbound' THEN 'Inbound'
            WHEN NULLIF(TRIM(t.sales_activity_type), '') = 'Email'
             AND NULLIF(TRIM(t.sales_activity_subtype), '') IS NULL
             AND t.task_subtype IN ('Email', 'ListEmail') THEN 'Outbound'
            ELSE TRIM(t.sales_activity_subtype)
        END                                                     AS activity_type,
        CASE
            WHEN TRIM(t.sales_activity_subtype) IN ('Engaged with partner', 'Email - Engaged with Partner') THEN 'Partner Activity'
            WHEN acc.account_type IN ('Distributor', 'Reseller') THEN 'Partner Activity'
            WHEN task_con.email_address IS NOT NULL
             AND SPLIT_PART(LOWER(task_con.email_address), '@', 2) LIKE '%autodesk%' THEN 'Internal Activity'
            ELSE 'Customer Activity'
        END                                                     AS activity_group,
        'EDH' AS source_system
    FROM {{ source('edh_shared', 'opportunity_task') }} AS t
    INNER JOIN {{ source('edh_shared', 'opportunity') }} AS o
        ON t.opportunity_number = o.opportunity_number
    LEFT JOIN {{ source('edh_shared', 'account_ced') }} AS acc
        ON o.end_customer_account_csn = acc.account_csn
    LEFT JOIN {{ source('edh_customer_private', 'contact') }} AS task_con
        ON t.end_customer_contact_csn = task_con.contact_csn
    WHERE t.task_status = 'Completed'
      AND t.source_created_ts >= DATEADD(day, -730, CURRENT_DATE)
      AND COALESCE(t.sales_activity_subtype, 'Blank') != 'Email - Bounced'
),

activities_construction AS (
    SELECT
        ct.task_id                                              AS activity_id,
        ca.autodesk_csn                                         AS account_csn,
        opp.opportunity_number__c                               AS opportunity_number,
        opp.id                                                  AS whatid,
        ct.owner_id                                             AS ownerid,
        COALESCE(edh_c.contact_csn, cc.contact_csn)             AS account_contact_csn,
        ct.task_subject                                         AS activity_subject,
        ct.task_type,
        ct.task_subtype,
        ct.task_status,
        TO_DATE(ct.date_created)                                AS activity_created_date,
        ct.date_created                                         AS activity_created_timestamp,
        TO_DATE(ct.date_activity)                               AS activity_date,
        ct.completed_date_time                                  AS activity_completed_timestamp,
        ct.call_outcome                                         AS cadence_activity_sub_type,
        ct.task_type_c                                          AS cadence_activity_type,
        ct.call_outcome                                         AS call_outcome,
        ct.call_type                                            AS call_type_raw,
        ct.outreach_call_duration_c                             AS outreach_call_duration_seconds,
        CASE
            WHEN NULLIF(TRIM(ct.task_type), '') IN ('Call', 'Connected Call') THEN 'Call'
            WHEN NULLIF(TRIM(ct.task_type), '') = 'Email' THEN 'Email'
            WHEN NULLIF(TRIM(ct.task_type), '') = 'Meeting' THEN 'Meeting'
            WHEN ct.task_subtype = 'Email' THEN 'Email'
            WHEN ct.task_subtype = 'Call' THEN 'Call'
            WHEN ct.task_subtype = 'Meeting' THEN 'Meeting'
            WHEN ct.task_subtype = 'Task'
             AND NULLIF(TRIM(ct.task_type), '') IN (
                 'Email', 'Email - Sent', 'Email - Response Received',
                 'Email - Engaged with Partner', 'Email - Bounced'
             ) THEN 'Email'
            WHEN ct.task_subtype = 'Task'
             AND (
                 NULLIF(TRIM(ct.task_type), '') IN (
                     'Meeting', 'Meeting completed', 'Meeting scheduled',
                     'Meeting missed / rescheduled', 'Intro Meeting',
                     'Follow-Up Meeting - Demo', 'Follow-Up Meeting - Discovery',
                     'New Key Contact Meeting', 'Set Appointment',
                     'Discovery/Demo Held', 'Discovery/Demo Scheduled', 'Demo Held'
                 )
                 OR NULLIF(TRIM(ct.task_type), '') ILIKE '%Meeting%'
             ) THEN 'Meeting'
            WHEN ct.task_subtype = 'Task'
             AND (
                 NULLIF(TRIM(ct.task_type), '') ILIKE 'LinkedIn:%'
                 OR NULLIF(TRIM(ct.task_type), '') IN (
                     'Sent Message', 'Sent Connect Request', 'Connect Accepted', 'Message Responded'
                 )
             ) THEN 'Social'
            WHEN ct.task_subtype = 'Task'
             AND NULLIF(TRIM(ct.task_type), '') IN (
                 'Connected', 'Connected Call', 'Left Message', 'Left Voicemail',
                 'No Answer', 'No answer, no vm', 'No Response', 'Abandoned',
                 'Discovery Call', 'Discovery Held', 'Discovery/Demo Held', 'Discovery/Demo Scheduled',
                 'Connected, Decision maker/influencer', 'Connected, Non Decision Maker',
                 'Connected, business conversation', 'Contacted', 'Transitioned to Call', 'First Call',
                 'Invalid Number', 'Invalid Phone Number', 'Invalid Contact',
                 'Incorrect/Invalid Phone Number', 'Wrong Number', 'Disconnected',
                 'Contact no longer with company', 'Not Decision Maker', 'Gatekeeper',
                 'Customer Not Interested', 'No Business Need', 'Competitor',
                 'Interest but no budget', 'No Budget', 'No Buying Timeframe',
                 'Information Requested', 'Information (Quote/Pricing/Product) Requested',
                 'Quote Requested', 'Quote Sent', 'Requested Pricing', 'Requested Product Info',
                 'Sales Conversation', 'Sales - Handoff', 'Sales Handoff',
                 'Handoff to Different Sales Group', 'Engaged with partner', 'Referred to partner',
                 'Support', 'Support Case', 'Support Account Management & Orders',
                 'Transfer to Support', 'Education', 'Renewals',
                 'Purchased', 'Already Purchased', 'Closed/Won', 'Cart link sent',
                 'Opportunity Update', 'Demo', 'Prospect Task',
                 'Do Not Contact', 'Partners/Vendors', 'Invalid'
             ) THEN 'Call'
            WHEN ct.task_subtype = 'Task'
             AND NULLIF(TRIM(ct.task_type), '') IN (
                 'Action Item', 'Other', 'Fallback', 'Account Task', 'Collaboration Task',
                 'Pipeline Task', 'Project Task', 'Project Team Recon', 'Account Support',
                 'SOF Processing', 'Re-Engage w/ Key Contact'
             ) THEN 'Task'
            WHEN NULLIF(TRIM(ct.task_subtype), '') IN ('Chat', 'Social', 'Update', 'ListEmail', 'Cadence')
                THEN ct.task_subtype
            ELSE COALESCE(NULLIF(TRIM(ct.task_subtype), ''), 'Task')
        END                                                     AS new_activity_type,
        CASE
            WHEN ct.task_subtype = 'Email'
              OR NULLIF(TRIM(ct.task_type), '') IN ('Email - Sent', 'Email - Engaged with Partner') THEN 'Outbound'
            WHEN NULLIF(TRIM(ct.task_type), '') = 'Email - Response Received' THEN 'Inbound'
            WHEN ct.task_subtype = 'Call' THEN COALESCE(ct.call_type, 'Outbound')
            WHEN NULLIF(TRIM(ct.task_type), '') IN ('Call', 'Connected Call') THEN COALESCE(ct.call_type, 'Outbound')
            WHEN ct.task_subtype = 'ListEmail' THEN 'Outbound'
            ELSE NULL
        END                                                     AS activity_type,
        CASE
            WHEN NULLIF(TRIM(ct.task_type), '') IN ('Engaged with partner', 'Email - Engaged with Partner')
              OR COALESCE(acc.account_type, ca.account_type) IN ('Distributor', 'Reseller') THEN 'Partner Activity'
            WHEN COALESCE(edh_c.email_address, cc.user_email) IS NOT NULL
             AND SPLIT_PART(LOWER(COALESCE(edh_c.email_address, cc.user_email)), '@', 2) LIKE '%autodesk%'
                THEN 'Internal Activity'
            ELSE 'Customer Activity'
        END                                                     AS activity_group,
        'Construction' AS source_system
    FROM {{ source('dw_salesforce', 'dim_salesforce_task') }} AS ct
    INNER JOIN {{ source('dw_salesforce', 'dim_salesforce_opportunities') }} AS opp
        ON ct.what_id = opp.id
    INNER JOIN {{ source('dw_salesforce', 'dim_salesforce_accounts') }} AS ca
        ON opp.account_id = ca.account_id
    LEFT JOIN {{ source('edh_shared', 'account_ced') }} AS acc
        ON ca.autodesk_csn = acc.account_csn
    LEFT JOIN {{ source('edh_shared', 'opportunity') }} AS edh_opp
        ON opp.opportunity_number__c = edh_opp.opportunity_number
    LEFT JOIN {{ source('dw_salesforce', 'dim_salesforce_contact') }} AS cc
        ON ct.sfdc_contact_id = cc.contact_id
    LEFT JOIN {{ source('edh_customer_private', 'contact') }} AS edh_c
        ON cc.contact_csn = edh_c.contact_csn
    WHERE ct.task_status = 'Completed'
      AND NOT ct.is_deleted
      AND ct.date_created >= DATEADD(day, -730, CURRENT_DATE)
      AND ct.TASK_TYPE != 'Email - Bounced'
      AND ca.autodesk_csn IS NOT NULL
      AND edh_opp.opportunity_number IS NULL
),

activities AS (
    SELECT * FROM activities_edh
    UNION ALL
    SELECT * FROM activities_construction
)

SELECT
    f.activity_id,
    f.source_system,
    f.account_csn,
    f.ownerid,
    f.account_contact_csn,
    f.opportunity_number,
    f.whatid,
    f.activity_created_date,
    f.activity_subject,
    f.task_type,
    f.task_subtype,
    f.task_status,
    f.activity_created_timestamp,
    f.activity_date,
    f.activity_completed_timestamp,
    f.cadence_activity_type,
    f.cadence_activity_sub_type,
    f.new_activity_type,
    f.activity_type,
    f.activity_group,
    f.call_outcome,
    f.call_type_raw,

    CASE
        WHEN f.new_activity_type = 'Call'
            THEN COALESCE(f.call_outcome, f.cadence_activity_sub_type)
    END AS calldisposition,

    CASE
        WHEN f.new_activity_type = 'Call'
            THEN COALESCE(
                NULLIF(f.outreach_call_duration_seconds, 0)::INT,
                CASE
                    WHEN f.activity_completed_timestamp IS NOT NULL
                     AND f.activity_created_timestamp IS NOT NULL
                     AND f.activity_completed_timestamp > f.activity_created_timestamp
                        THEN DATEDIFF('second', f.activity_created_timestamp, f.activity_completed_timestamp)
                END
            )
    END AS calldurationinseconds,

    CASE
        WHEN f.new_activity_type = 'Call'
         AND f.activity_type = 'Outbound'
         AND f.activity_group = 'Customer Activity' THEN 1 ELSE 0
    END AS call_attempt_outbound,

    CASE
        WHEN f.new_activity_type = 'Call'
         AND f.activity_type = 'Outbound'
         AND f.activity_group = 'Customer Activity'
         AND (
            (f.source_system = 'EDH'
             AND f.cadence_activity_sub_type IN (
                 'Connected', 'Connected, Decision maker/influencer',
                 'Connected, business conversation', 'Connected, Non Decision Maker',
                 'Discovery call', 'Customer Not Interested'
             ))
            OR (f.source_system = 'Construction'
             AND f.call_outcome IN (
                 'Qualified', 'Answered - Leave in Sequence (CS ONLY)', 'Gate Keeper - Follow Up',
                 'No Timeline', 'No Authority', 'Open S2+ Opportunity', 'Prospect Refused To Talk',
                 'Sales - Working', 'No Budget', 'Uses Competitor', 'Follow up within 30 Days',
                 'Active License'
             ))
         ) THEN 1 ELSE 0
    END AS call_connected_outbound,

    CASE
        WHEN f.new_activity_type = 'Meeting'
         AND f.activity_group = 'Customer Activity'
         AND (
            (f.source_system = 'EDH'
             AND f.activity_type = 'Outbound'
             AND f.cadence_activity_sub_type = 'Meeting scheduled')
            OR (f.source_system = 'Construction'
             AND f.task_type IN ('Meeting scheduled', 'Set Appointment', 'Discovery/Demo Scheduled'))
         ) THEN 1 ELSE 0
    END AS meeting_scheduled,

    CASE
        WHEN f.new_activity_type IN ('Meeting', 'Call')
         AND (
            (f.source_system = 'EDH'
             AND f.cadence_activity_sub_type IN ('Meeting completed', 'Discovery/Demo Held', 'Demo Held'))
            OR (f.source_system = 'Construction'
             AND f.task_type IN (
                 'Meeting completed', 'Discovery/Demo Held', 'Demo Held', 'Demo',
                 'Discovery Call', 'Discovery Held'
             ))
         ) THEN 1 ELSE 0
    END AS meeting_completed,

    CASE
        WHEN f.new_activity_type = 'Email'
         AND f.activity_type = 'Outbound'
         AND f.activity_group = 'Customer Activity' THEN 1 ELSE 0
    END AS email_attempt_outbound,

    CASE
        WHEN f.new_activity_type = 'Email'
         AND f.activity_type = 'Inbound'
         AND f.activity_group = 'Customer Activity' THEN 1 ELSE 0
    END AS email_received

FROM activities AS f
WHERE f.activity_created_date >= '2026-02-01'
