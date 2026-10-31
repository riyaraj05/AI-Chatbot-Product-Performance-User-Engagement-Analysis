-- =====================================================================
-- 04_repeat_usage.sql
-- Does the quality of the FIRST conversation determine whether users come back?
-- =====================================================================

-- Q: first_conversation_outcome_vs_return
-- ROW_NUMBER isolates each user's first conversation.
-- "Returned" = another conversation within 14 days after the first one.
WITH ranked AS (
    SELECT
        c.*,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY started_at) AS rn
    FROM conversations c
),
first_conv AS (SELECT * FROM ranked WHERE rn = 1),
returned AS (
    SELECT f.user_id,
           MAX(CASE WHEN julianday(c.started_at) - julianday(f.started_at) > 0
                     AND julianday(c.started_at) - julianday(f.started_at) <= 14 THEN 1 ELSE 0 END) AS returned_14d
    FROM first_conv f
    JOIN conversations c ON c.user_id = f.user_id
    GROUP BY f.user_id
)
SELECT
    CASE WHEN f.resolved = 1 THEN 'first chat resolved' ELSE 'first chat unresolved' END AS first_chat_outcome,
    COUNT(*) AS users,
    ROUND(100.0 * AVG(r.returned_14d), 1) AS return_within_14d_pct
FROM first_conv f
JOIN returned r ON r.user_id = f.user_id
-- only users who had at least 14 days of follow-up in the data
WHERE julianday((SELECT MAX(started_at) FROM conversations)) - julianday(f.started_at) >= 14
GROUP BY first_chat_outcome;

-- Q: first_conversation_latency_vs_return
WITH ranked AS (
    SELECT c.*, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY started_at) AS rn
    FROM conversations c
),
first_conv AS (SELECT * FROM ranked WHERE rn = 1),
returned AS (
    SELECT f.user_id,
           MAX(CASE WHEN julianday(c.started_at) - julianday(f.started_at) > 0
                     AND julianday(c.started_at) - julianday(f.started_at) <= 14 THEN 1 ELSE 0 END) AS returned_14d
    FROM first_conv f JOIN conversations c ON c.user_id = f.user_id
    GROUP BY f.user_id
)
SELECT
    CASE
        WHEN f.avg_response_latency_ms < 2000 THEN '1) <2s'
        WHEN f.avg_response_latency_ms < 3500 THEN '2) 2-3.5s'
        ELSE '3) 3.5s+'
    END AS first_chat_latency,
    COUNT(*) AS users,
    ROUND(100.0 * AVG(r.returned_14d), 1) AS return_within_14d_pct
FROM first_conv f
JOIN returned r ON r.user_id = f.user_id
WHERE julianday((SELECT MAX(started_at) FROM conversations)) - julianday(f.started_at) >= 14
GROUP BY first_chat_latency
ORDER BY first_chat_latency;

-- Q: first_conversation_intent_vs_return
WITH ranked AS (
    SELECT c.*, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY started_at) AS rn
    FROM conversations c
),
first_conv AS (SELECT * FROM ranked WHERE rn = 1),
returned AS (
    SELECT f.user_id,
           MAX(CASE WHEN julianday(c.started_at) - julianday(f.started_at) > 0
                     AND julianday(c.started_at) - julianday(f.started_at) <= 14 THEN 1 ELSE 0 END) AS returned_14d
    FROM first_conv f JOIN conversations c ON c.user_id = f.user_id
    GROUP BY f.user_id
)
SELECT
    f.intent AS first_chat_intent,
    COUNT(*) AS users,
    ROUND(100.0 * AVG(f.resolved), 1)     AS first_chat_completion_pct,
    ROUND(100.0 * AVG(r.returned_14d), 1) AS return_within_14d_pct
FROM first_conv f
JOIN returned r ON r.user_id = f.user_id
WHERE julianday((SELECT MAX(started_at) FROM conversations)) - julianday(f.started_at) >= 14
GROUP BY f.intent
ORDER BY return_within_14d_pct DESC;

-- Q: weekly_cohort_retention
-- Cohort = week of first conversation. Retention = share of the cohort active N weeks later.
WITH first_conv AS (
    SELECT user_id, MIN(date(started_at)) AS first_day FROM conversations GROUP BY user_id
),
activity AS (
    SELECT DISTINCT c.user_id,
           CAST((julianday(date(c.started_at)) - julianday(f.first_day)) / 7 AS INTEGER) AS week_number
    FROM conversations c
    JOIN first_conv f ON f.user_id = c.user_id
),
cohorts AS (
    SELECT user_id, strftime('%Y-%m', first_day) AS cohort_month FROM first_conv
),
cohort_size AS (SELECT cohort_month, COUNT(*) AS n FROM cohorts GROUP BY cohort_month)
SELECT
    co.cohort_month,
    cs.n AS cohort_users,
    a.week_number,
    COUNT(DISTINCT a.user_id) AS active_users,
    ROUND(100.0 * COUNT(DISTINCT a.user_id) / cs.n, 1) AS retention_pct
FROM activity a
JOIN cohorts co ON co.user_id = a.user_id
JOIN cohort_size cs ON cs.cohort_month = co.cohort_month
WHERE a.week_number <= 8
GROUP BY co.cohort_month, cs.n, a.week_number
ORDER BY co.cohort_month, a.week_number;

-- Q: conversations_per_user_distribution
WITH per_user AS (SELECT user_id, COUNT(*) AS n FROM conversations GROUP BY user_id)
SELECT
    CASE WHEN n >= 6 THEN '6+' ELSE CAST(n AS TEXT) END AS conversations_per_user,
    COUNT(*) AS users,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_users
FROM per_user
GROUP BY conversations_per_user
ORDER BY conversations_per_user;
