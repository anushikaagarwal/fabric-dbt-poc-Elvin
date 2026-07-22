WITH activities_edh AS (
    SELECT
        t.TASK_ID                                                       AS activity_id,
        o.END_CUSTOMER_ACCOUNT_CSN                                      AS account_csn,
        o.OPPORTUNITY_NUMBER                                            AS opportunity_number,
        o.SOURCE_RECORD_ID                                              AS whatid,
        t.ASSIGNED_TO_EMPLOYEE_NUMBER                                   AS ownerid,
        t.END_CUSTOMER_CONTACT_CSN                                      AS account_contact_csn,
        t.SUBJECT_LINE                                                  AS activity_subject,
        t.TASK_TYPE                                                     AS task_type,
        t.TASK_SUBTYPE                                                  AS task_subtype,
        t.TASK_STATUS                                                   AS task_status,
        CAST(t.SOURCE_CREATED_TS AS DATE)                               AS activity_created_date,
        t.SOURCE_CREATED_TS                                             AS activity_created_timestamp,
        CAST(t.TASK_ACTIVITY_DATE AS DATE)                              AS activity_date,
        t.TASK_COMPLETED_TS                                             AS activity_completed_timestamp,
        TRIM(t.SALES_ACTIVITY_SUBTYPE)                                  AS cadence_activity_sub_type,
        TRIM(t.SALES_ACTIVITY_TYPE)                                     AS cadence_activity_type,
        CAST(NULL AS VARCHAR(255))                                      AS call_outcome,
        CAST(NULL AS VARCHAR(255))                                      AS call_type_raw,
        CAST(NULL AS FLOAT)                                             AS outreach_call_duration_seconds,
        CASE
            WHEN t.TASK_SUBTYPE = 'Task' AND NULLIF(TRIM(t.SALES_ACTIVITY_TYPE), '') = 'Call' THEN 'Call'
            WHEN t.TASK_SUBTYPE = 'Call' AND NULLIF(TRIM(t.SALES_ACTIVITY_TYPE), '') = 'Meeting' THEN 'Meeting'
            WHEN t.TASK_SUBTYPE = 'Task' AND NULLIF(TRIM(t.SALES_ACTIVITY_TYPE), '') = 'Email' THEN 'Email'
            WHEN t.TASK_SUBTYPE = 'Task' AND NULLIF(TRIM(t.SALES_ACTIVITY_TYPE), '') IS NULL
                 AND t.SALES_ACTIVITY_SUBTYPE = 'Email - Response Received' THEN 'Email'
            WHEN t.TASK_SUBTYPE = 'Task' AND NULLIF(TRIM(t.SALES_ACTIVITY_TYPE), '') IS NULL
                 AND LOWER(t.SUBJECT_LINE) LIKE '%sub-call%' THEN 'Call'
            WHEN t.TASK_SUBTYPE = 'Task' AND NULLIF(TRIM(t.SALES_ACTIVITY_TYPE), '') IS NULL
                 AND LOWER(t.SUBJECT_LINE) LIKE '%inmail%' THEN 'Email'
            WHEN t.TASK_SUBTYPE = 'Task' AND NULLIF(TRIM(t.SALES_ACTIVITY_TYPE), '') IS NULL
                 AND LOWER(t.TASK_DESCRIPTION) LIKE '%external email%' THEN 'Email'
            WHEN t.TASK_SUBTYPE = 'Task' AND NULLIF(TRIM(t.SALES_ACTIVITY_TYPE), '') IS NULL
                 AND LOWER(t.TASK_DESCRIPTION) LIKE '%email sent successfully%' THEN 'Email'
            WHEN t.TASK_SUBTYPE = 'Task'
             AND NULLIF(TRIM(t.SALES_ACTIVITY_TYPE), '') IN ('Chat', 'Meeting', 'Social', 'Update')
                THEN TRIM(t.SALES_ACTIVITY_TYPE)
            WHEN NULLIF(TRIM(t.SALES_ACTIVITY_TYPE), '') IN ('Call', 'Scheduled Call') THEN 'Call'
            WHEN NULLIF(TRIM(t.SALES_ACTIVITY_TYPE), '') = 'Email' THEN 'Email'
            WHEN NULLIF(TRIM(t.SALES_ACTIVITY_TYPE), '') = 'Meeting' THEN 'Meeting'
            WHEN NULLIF(TRIM(t.SALES_ACTIVITY_TYPE), '') IN ('Chat', 'Social', 'Update') THEN TRIM(t.SALES_ACTIVITY_TYPE)
            ELSE COALESCE(NULLIF(TRIM(t.TASK_SUBTYPE), ''), 'Task')
        END                                                             AS new_activity_type,
        CASE
            WHEN TRIM(t.SALES_ACTIVITY_SUBTYPE) = 'Email - Sent' THEN 'Outbound'
            WHEN TRIM(t.SALES_ACTIVITY_SUBTYPE) = 'Email - Response Received' THEN 'Inbound'
            WHEN TRIM(t.SALES_ACTIVITY_SUBTYPE) = 'Email - Engaged with Partner' THEN 'Outbound'
            WHEN NULLIF(TRIM(t.SALES_ACTIVITY_TYPE), '') IN ('Call', 'Scheduled Call') OR t.TASK_SUBTYPE = 'Call' THEN 'Outbound'
            WHEN NULLIF(TRIM(t.SALES_ACTIVITY_TYPE), '') = 'Email' AND t.TASK_TYPE = 'Inbound' THEN 'Inbound'
            WHEN NULLIF(TRIM(t.SALES_ACTIVITY_TYPE), '') = 'Email'
             AND NULLIF(TRIM(t.SALES_ACTIVITY_SUBTYPE), '') IS NULL
             AND t.TASK_SUBTYPE IN ('Email', 'ListEmail') THEN 'Outbound'
            ELSE TRIM(t.SALES_ACTIVITY_SUBTYPE)
        END                                                             AS activity_type,
        CASE
            WHEN TRIM(t.SALES_ACTIVITY_SUBTYPE) IN ('Engaged with partner', 'Email - Engaged with Partner') THEN 'Partner Activity'
            WHEN acc.ACCOUNT_TYPE IN ('Distributor', 'Reseller') THEN 'Partner Activity'
            WHEN task_con.EMAIL_ADDRESS IS NOT NULL
             AND SUBSTRING(
                 LOWER(task_con.EMAIL_ADDRESS),
                 CHARINDEX('@', LOWER(task_con.EMAIL_ADDRESS)) + 1,
                 LEN(LOWER(task_con.EMAIL_ADDRESS))
             ) LIKE '%autodesk%' THEN 'Internal Activity'
            ELSE 'Customer Activity'
        END                                                             AS activity_group,
        'EDH' AS source_system
    FROM {{ source('edh_shared', 'opportunity_task') }} AS t
    INNER JOIN {{ source('edh_shared', 'opportunity') }} AS o
        ON t.OPPORTUNITY_NUMBER = o.OPPORTUNITY_NUMBER
    LEFT JOIN {{ source('edh_shared', 'account_ced') }} AS acc
        ON o.END_CUSTOMER_ACCOUNT_CSN = acc.ACCOUNT_CSN
    LEFT JOIN {{ source('edh_customer_private', 'contact') }} AS task_con
        ON t.END_CUSTOMER_CONTACT_CSN = task_con.CONTACT_CSN
    WHERE t.TASK_STATUS = 'Completed'
      AND t.SOURCE_CREATED_TS >= DATEADD(day, -730, CAST(GETDATE() AS DATE))
      AND COALESCE(t.SALES_ACTIVITY_SUBTYPE, 'Blank') != 'Email - Bounced'
),

activities_construction AS (
    SELECT
        ct.TASK_ID                                                      AS activity_id,
        ca.AUTODESK_CSN                                                 AS account_csn,
        opp.OPPORTUNITY_NUMBER__C                                       AS opportunity_number,
        opp.ID                                                          AS whatid,
        ct.OWNER_ID                                                     AS ownerid,
        COALESCE(edh_c.CONTACT_CSN, cc.CONTACT_CSN)                     AS account_contact_csn,
        ct.TASK_SUBJECT                                                 AS activity_subject,
        ct.TASK_TYPE                                                    AS task_type,
        ct.TASK_SUBTYPE                                                 AS task_subtype,
        ct.TASK_STATUS                                                  AS task_status,
        CAST(ct.DATE_CREATED AS DATE)                                   AS activity_created_date,
        ct.DATE_CREATED                                                 AS activity_created_timestamp,
        CAST(ct.DATE_ACTIVITY AS DATE)                                  AS activity_date,
        ct.COMPLETED_DATE_TIME                                          AS activity_completed_timestamp,
        ct.CALL_OUTCOME                                                 AS cadence_activity_sub_type,
        ct.TASK_TYPE_C                                                  AS cadence_activity_type,
        ct.CALL_OUTCOME                                                 AS call_outcome,
        ct.CALL_TYPE                                                    AS call_type_raw,
        ct.OUTREACH_CALL_DURATION_C                                     AS outreach_call_duration_seconds,
        CASE
            WHEN NULLIF(TRIM(ct.TASK_TYPE), '') IN ('Call', 'Connected Call') THEN 'Call'
            WHEN NULLIF(TRIM(ct.TASK_TYPE), '') = 'Email' THEN 'Email'
            WHEN NULLIF(TRIM(ct.TASK_TYPE), '') = 'Meeting' THEN 'Meeting'
            WHEN ct.TASK_SUBTYPE = 'Email' THEN 'Email'
            WHEN ct.TASK_SUBTYPE = 'Call' THEN 'Call'
            WHEN ct.TASK_SUBTYPE = 'Meeting' THEN 'Meeting'
            WHEN ct.TASK_SUBTYPE = 'Task'
             AND NULLIF(TRIM(ct.TASK_TYPE), '') IN (
                 'Email', 'Email - Sent', 'Email - Response Received',
                 'Email - Engaged with Partner', 'Email - Bounced'
             ) THEN 'Email'
            WHEN ct.TASK_SUBTYPE = 'Task'
             AND (
                 NULLIF(TRIM(ct.TASK_TYPE), '') IN (
                     'Meeting', 'Meeting completed', 'Meeting scheduled',
                     'Meeting missed / rescheduled', 'Intro Meeting',
                     'Follow-Up Meeting - Demo', 'Follow-Up Meeting - Discovery',
                     'New Key Contact Meeting', 'Set Appointment',
                     'Discovery/Demo Held', 'Discovery/Demo Scheduled', 'Demo Held'
                 )
                 OR LOWER(NULLIF(TRIM(ct.TASK_TYPE), '')) LIKE '%meeting%'
             ) THEN 'Meeting'
            WHEN ct.TASK_SUBTYPE = 'Task'
             AND (
                 LOWER(NULLIF(TRIM(ct.TASK_TYPE), '')) LIKE 'linkedin:%'
                 OR NULLIF(TRIM(ct.TASK_TYPE), '') IN (
                     'Sent Message', 'Sent Connect Request', 'Connect Accepted', 'Message Responded'
                 )
             ) THEN 'Social'
            WHEN ct.TASK_SUBTYPE = 'Task'
             AND NULLIF(TRIM(ct.TASK_TYPE), '') IN (
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
            WHEN ct.TASK_SUBTYPE = 'Task'
             AND NULLIF(TRIM(ct.TASK_TYPE), '') IN (
                 'Action Item', 'Other', 'Fallback', 'Account Task', 'Collaboration Task',
                 'Pipeline Task', 'Project Task', 'Project Team Recon', 'Account Support',
                 'SOF Processing', 'Re-Engage w/ Key Contact'
             ) THEN 'Task'
            WHEN NULLIF(TRIM(ct.TASK_SUBTYPE), '') IN ('Chat', 'Social', 'Update', 'ListEmail', 'Cadence')
                THEN ct.TASK_SUBTYPE
            ELSE COALESCE(NULLIF(TRIM(ct.TASK_SUBTYPE), ''), 'Task')
        END                                                             AS new_activity_type,
        CASE
            WHEN ct.TASK_SUBTYPE = 'Email'
              OR NULLIF(TRIM(ct.TASK_TYPE), '') IN ('Email - Sent', 'Email - Engaged with Partner') THEN 'Outbound'
            WHEN NULLIF(TRIM(ct.TASK_TYPE), '') = 'Email - Response Received' THEN 'Inbound'
            WHEN ct.TASK_SUBTYPE = 'Call' THEN COALESCE(ct.CALL_TYPE, 'Outbound')
            WHEN NULLIF(TRIM(ct.TASK_TYPE), '') IN ('Call', 'Connected Call') THEN COALESCE(ct.CALL_TYPE, 'Outbound')
            WHEN ct.TASK_SUBTYPE = 'ListEmail' THEN 'Outbound'
            ELSE NULL
        END                                                             AS activity_type,
        CASE
            WHEN NULLIF(TRIM(ct.TASK_TYPE), '') IN ('Engaged with partner', 'Email - Engaged with Partner')
              OR COALESCE(acc.ACCOUNT_TYPE, ca.ACCOUNT_TYPE) IN ('Distributor', 'Reseller') THEN 'Partner Activity'
            WHEN COALESCE(edh_c.EMAIL_ADDRESS, cc.USER_EMAIL) IS NOT NULL
             AND SUBSTRING(
                 LOWER(COALESCE(edh_c.EMAIL_ADDRESS, cc.USER_EMAIL)),
                 CHARINDEX('@', LOWER(COALESCE(edh_c.EMAIL_ADDRESS, cc.USER_EMAIL))) + 1,
                 LEN(LOWER(COALESCE(edh_c.EMAIL_ADDRESS, cc.USER_EMAIL)))
             ) LIKE '%autodesk%'
                THEN 'Internal Activity'
            ELSE 'Customer Activity'
        END                                                             AS activity_group,
        'Construction' AS source_system
    FROM {{ source('dw_salesforce', 'dim_salesforce_task') }} AS ct
    INNER JOIN {{ source('dw_salesforce', 'dim_salesforce_opportunities') }} AS opp
        ON ct.WHAT_ID = opp.ID
    INNER JOIN {{ source('dw_salesforce', 'dim_salesforce_accounts') }} AS ca
        ON opp.ACCOUNT_ID = ca.ACCOUNT_ID
    LEFT JOIN {{ source('edh_shared', 'account_ced') }} AS acc
        ON ca.AUTODESK_CSN = acc.ACCOUNT_CSN
    LEFT JOIN {{ source('edh_shared', 'opportunity') }} AS edh_opp
        ON opp.OPPORTUNITY_NUMBER__C = edh_opp.OPPORTUNITY_NUMBER
    LEFT JOIN {{ source('dw_salesforce', 'dim_salesforce_contact') }} AS cc
        ON ct.SFDC_CONTACT_ID = cc.CONTACT_ID
    LEFT JOIN {{ source('edh_customer_private', 'contact') }} AS edh_c
        ON cc.CONTACT_CSN = edh_c.CONTACT_CSN
    WHERE ct.TASK_STATUS = 'Completed'
      AND COALESCE(ct.IS_DELETED, 0) = 0
      AND ct.DATE_CREATED >= DATEADD(day, -730, CAST(GETDATE() AS DATE))
      AND ct.TASK_TYPE != 'Email - Bounced'
      AND ca.AUTODESK_CSN IS NOT NULL
      AND edh_opp.OPPORTUNITY_NUMBER IS NULL
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
                CAST(NULLIF(f.outreach_call_duration_seconds, 0) AS INT),
                CASE
                    WHEN f.activity_completed_timestamp IS NOT NULL
                     AND f.activity_created_timestamp IS NOT NULL
                     AND f.activity_completed_timestamp > f.activity_created_timestamp
                        THEN DATEDIFF(
                            second,
                            f.activity_created_timestamp,
                            f.activity_completed_timestamp
                        )
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
WHERE f.activity_created_date >= CAST('2026-02-01' AS DATE)
