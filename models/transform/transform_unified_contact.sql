WITH edh_contacts AS (
    SELECT
        c.contact_csn,
        c.first_name                                                    AS contact_first_name,
        c.last_name                                                     AS contact_last_name,
        c.email_address                                                 AS contact_email,
        c.contact_phone_number                                          AS contact_phone,
        CASE
            WHEN c.email_address IS NOT NULL
                THEN SPLIT_PART(LOWER(c.email_address), '@', 2)
        END                                                             AS contact_email_domain,
        'EDH'                                                           AS source_system
    FROM {{ source('edh_customer_private', 'contact') }} AS c
    WHERE c.contact_csn IS NOT NULL
),

acs_only_contacts AS (
    SELECT
        cc.contact_csn,
        cc.first_name                                                   AS contact_first_name,
        cc.last_name                                                    AS contact_last_name,
        cc.user_email                                                   AS contact_email,
        cc.phone                                                        AS contact_phone,
        CASE
            WHEN cc.user_email IS NOT NULL
                THEN SPLIT_PART(LOWER(cc.user_email), '@', 2)
        END                                                             AS contact_email_domain,
        'ACS'                                                           AS source_system
    FROM {{ source('dw_salesforce', 'dim_salesforce_contact') }} AS cc
    LEFT JOIN {{ source('edh_customer_private', 'contact') }} AS edh
        ON cc.contact_csn = edh.contact_csn
    WHERE cc.contact_csn IS NOT NULL
      AND edh.contact_csn IS NULL
)

SELECT * FROM edh_contacts
UNION ALL
SELECT * FROM acs_only_contacts
