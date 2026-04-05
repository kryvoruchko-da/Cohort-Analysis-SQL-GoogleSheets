WITH users_parsed AS (
    -- CTE 1: Cleaning text dates and converting them to TIMESTAMP format for the users table --
    SELECT 
        user_id, 
        promo_signup_flag,
        CASE 
            WHEN clean_date ~ '^\d{4}-\d{1,2}-\d{1,2}$' THEN to_date(clean_date, 'YYYY-MM-DD')
            WHEN clean_date ~ '^\d{1,2}-\d{1,2}-\d{4}$' THEN to_date(clean_date, 'DD-MM-YYYY')
            WHEN clean_date ~ '^\d{1,2}-\d{1,2}-\d{2}$' THEN to_date(clean_date, 'DD-MM-YY')
            ELSE NULL 
        END AS signup_ts
    FROM (
    -- Nested subquery to unify delimiters and remove extra spaces/time
        SELECT *, regexp_replace(split_part(trim(signup_datetime), ' ', 1), '[./]', '-', 'g') AS clean_date 
        FROM cohort_users_raw
    ) AS sub
),
events_parsed AS (
    -- CTE 2: Cleaning and preparing activity (event) dates --
    SELECT 
        user_id, 
        event_type,
        CASE 
            WHEN clean_date ~ '^\d{4}-\d{1,2}-\d{1,2}$' THEN to_date(clean_date, 'YYYY-MM-DD')
            WHEN clean_date ~ '^\d{1,2}-\d{1,2}-\d{4}$' THEN to_date(clean_date, 'DD-MM-YYYY')
            WHEN clean_date ~ '^\d{1,2}-\d{1,2}-\d{2}$' THEN to_date(clean_date, 'DD-MM-YY')
            ELSE NULL 
        END AS event_ts
    FROM (
    -- Similar cleaning logic for the events table
        SELECT *, regexp_replace(split_part(trim(event_datetime), ' ', 1), '[./]', '-', 'g') AS clean_date 
        FROM cohort_events_raw
    ) AS sub
),
user_activity AS (
    -- CTE 3: Joining users with events and calculating core cohort metrics  --
    SELECT
        u.user_id,
        u.promo_signup_flag,
        -- Truncating dates to the beginning of the month to define cohorts
        DATE_TRUNC('month', u.signup_ts)::date AS cohort_month,
        DATE_TRUNC('month', e.event_ts)::date AS activity_month,
        -- Calculating month_offset (month difference between registration and event)
        (EXTRACT(year FROM e.event_ts) - EXTRACT(year FROM u.signup_ts)) * 12 +
        (EXTRACT(month FROM e.event_ts) - EXTRACT(month FROM u.signup_ts)) AS month_offset
    FROM users_parsed u
    JOIN events_parsed e ON u.user_id = e.user_id
    WHERE 
        u.signup_ts IS NOT NULL            -- Filtering out records without a registration date
        AND e.event_ts IS NOT NULL         -- Filtering out events without a date
        AND e.event_type IS NOT NULL       -- Ignoring empty event types
        AND e.event_type <> 'test_event'   -- Excluding test data   
)

-- FINAL SELECT: Aggregating data for Google Sheets reporting --
SELECT
    promo_signup_flag,
    cohort_month,
    month_offset,
    -- Calculating the number of unique users for each cohort and month offset
    COUNT(DISTINCT user_id) AS users_total
FROM user_activity
WHERE 
-- Limiting the observation window per requirements (Jan-Jun 2025)
    activity_month BETWEEN '2025-01-01' AND '2025-06-01'
GROUP BY 
    promo_signup_flag,
    cohort_month,
    month_offset
ORDER BY 
    promo_signup_flag, 
    cohort_month, 
    month_offset;