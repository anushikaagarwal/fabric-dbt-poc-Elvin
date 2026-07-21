WITH edh_employees AS (
    SELECT
        ed.worker_id                                                    AS employee_id,
        ed.preferred_name                                               AS employee_name,
        ed.sales_role,
        ed.manager_display_name                                         AS manager_name,
        ed.work_email,
        'EDH'                                                           AS source_system
    FROM {{ source('edh_shared', 'employee_ced') }} AS ed
    WHERE ed.is_active = TRUE
      AND ed.worker_id IS NOT NULL
),

acs_only_users AS (
    SELECT
        u.user_id                                                       AS employee_id,
        NULL::VARCHAR                                                   AS employee_name,
        NULL::VARCHAR                                                   AS sales_role,
        u.manager_name,
        u.user_email                                                    AS work_email,
        'ACS'                                                           AS source_system
    FROM {{ source('dw_salesforce', 'dim_salesforce_users') }} AS u
    LEFT JOIN {{ source('edh_shared', 'employee_ced') }} AS ed
        ON u.user_id = ed.worker_id
    WHERE u.user_id IS NOT NULL
      AND ed.worker_id IS NULL
)

SELECT * FROM edh_employees
UNION ALL
SELECT * FROM acs_only_users
