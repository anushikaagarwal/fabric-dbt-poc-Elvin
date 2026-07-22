WITH edh_employees AS (
    SELECT
        ed.WORKER_ID                                                    AS employee_id,
        ed.PREFERRED_NAME                                               AS employee_name,
        ed.SALES_ROLE                                                   AS sales_role,
        ed.MANAGER_DISPLAY_NAME                                         AS manager_name,
        ed.WORK_EMAIL                                                   AS work_email,
        'EDH'                                                           AS source_system
    FROM {{ source('edh_shared', 'employee_ced') }} AS ed
    WHERE ed.IS_ACTIVE = 1
      AND ed.WORKER_ID IS NOT NULL
),

acs_only_users AS (
    SELECT
        u.USER_ID                                                       AS employee_id,
        CAST(NULL AS VARCHAR(255))                                      AS employee_name,
        CAST(NULL AS VARCHAR(255))                                      AS sales_role,
        u.MANAGER_NAME                                                  AS manager_name,
        u.USER_EMAIL                                                    AS work_email,
        'ACS'                                                           AS source_system
    FROM {{ source('dw_salesforce', 'dim_salesforce_users') }} AS u
    LEFT JOIN {{ source('edh_shared', 'employee_ced') }} AS ed
        ON u.USER_ID = ed.WORKER_ID
    WHERE u.USER_ID IS NOT NULL
      AND ed.WORKER_ID IS NULL
)

SELECT * FROM edh_employees
UNION ALL
SELECT * FROM acs_only_users
