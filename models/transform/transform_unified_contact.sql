WITH edh_contacts AS (
    SELECT
        c.CONTACT_CSN                                                   AS contact_csn,
        c.FIRST_NAME                                                    AS contact_first_name,
        c.LAST_NAME                                                     AS contact_last_name,
        c.EMAIL_ADDRESS                                                 AS contact_email,
        c.CONTACT_PHONE_NUMBER                                          AS contact_phone,
        CASE
            WHEN c.EMAIL_ADDRESS IS NOT NULL
                THEN SUBSTRING(
                    LOWER(c.EMAIL_ADDRESS),
                    CHARINDEX('@', LOWER(c.EMAIL_ADDRESS)) + 1,
                    LEN(LOWER(c.EMAIL_ADDRESS))
                )
        END                                                             AS contact_email_domain,
        'EDH'                                                           AS source_system
    FROM {{ source('edh_customer_private', 'contact') }} AS c
    WHERE c.CONTACT_CSN IS NOT NULL
),

acs_only_contacts AS (
    SELECT
        cc.CONTACT_CSN                                                  AS contact_csn,
        cc.FIRST_NAME                                                   AS contact_first_name,
        cc.LAST_NAME                                                    AS contact_last_name,
        cc.USER_EMAIL                                                   AS contact_email,
        cc.PHONE                                                        AS contact_phone,
        CASE
            WHEN cc.USER_EMAIL IS NOT NULL
                THEN SUBSTRING(
                    LOWER(cc.USER_EMAIL),
                    CHARINDEX('@', LOWER(cc.USER_EMAIL)) + 1,
                    LEN(LOWER(cc.USER_EMAIL))
                )
        END                                                             AS contact_email_domain,
        'ACS'                                                           AS source_system
    FROM {{ source('dw_salesforce', 'dim_salesforce_contact') }} AS cc
    LEFT JOIN {{ source('edh_customer_private', 'contact') }} AS edh
        ON cc.CONTACT_CSN = edh.CONTACT_CSN
    WHERE cc.CONTACT_CSN IS NOT NULL
      AND edh.CONTACT_CSN IS NULL
)

SELECT * FROM edh_contacts
UNION ALL
SELECT * FROM acs_only_contacts
