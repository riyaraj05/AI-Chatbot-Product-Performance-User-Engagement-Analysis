-- =====================================================================
-- 02_adoption_engagement.sql
-- Adoption: do signups start using the chatbot? Engagement: how often and how many?
-- Definitions:
--   Activated user  = started at least one conversation within 7 days of signup
--   Active user     = started at least one conversation in the period
--   Stickiness      = average DAU / MAU
-- =====================================================================

-- Q: activation_rate_by_signup_month
SELECT
    strftime('%Y-%m', u.signup_date) AS signup_month,
    COUNT(*) AS signups,
    SUM(CASE WHEN a.user_id IS NOT NULL THEN 1 ELSE 0 END) AS activated,
    ROUND(100.0 * SUM(CASE WHEN a.user_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS activation_rate_pct
FROM users u
LEFT JOIN (
    SELECT DISTINCT c.user_id
    FROM conversations c
    JOIN users u2 ON u2.user_id = c.user_id
    WHERE julianday(date(c.started_at)) - julianday(u2.signup_date) <= 7
) a ON a.user_id = u.user_id
GROUP BY signup_month
ORDER BY signup_month;

-- Q: activation_by_plan_platform
SELECT
    u.plan, u.platform,
    COUNT(*) AS signups,
    ROUND(100.0 * COUNT(DISTINCT c.user_id) / COUNT(*), 1) AS ever_used_pct
FROM users u
LEFT JOIN conversations c ON c.user_id = u.user_id
GROUP BY u.plan, u.platform
ORDER BY u.plan, u.platform;

-- Q: weekly_active_users
-- LAG gives last week's value so we can compute week-over-week growth.
WITH weekly AS (
    SELECT
        strftime('%Y-W%W', started_at) AS week,
        COUNT(DISTINCT user_id)        AS active_users,
        COUNT(*)                       AS conversations
    FROM conversations
    GROUP BY week
)
SELECT
    week, active_users, conversations,
    ROUND(1.0 * conversations / active_users, 2) AS conv_per_active_user,
    ROUND(100.0 * (active_users - LAG(active_users) OVER (ORDER BY week))
          / LAG(active_users) OVER (ORDER BY week), 1) AS wau_wow_pct
FROM weekly
ORDER BY week;

-- Q: new_vs_returning_users_weekly
-- "New" = the week of the user's first-ever conversation.
WITH first_week AS (
    SELECT user_id, MIN(strftime('%Y-W%W', started_at)) AS first_week
    FROM conversations GROUP BY user_id
),
activity AS (
    SELECT DISTINCT user_id, strftime('%Y-W%W', started_at) AS week FROM conversations
)
SELECT
    a.week,
    SUM(CASE WHEN a.week = f.first_week THEN 1 ELSE 0 END) AS new_users,
    SUM(CASE WHEN a.week > f.first_week THEN 1 ELSE 0 END) AS returning_users
FROM activity a
JOIN first_week f ON f.user_id = a.user_id
GROUP BY a.week
ORDER BY a.week;

-- Q: dau_mau_stickiness
WITH daily AS (
    SELECT date(started_at) AS day, strftime('%Y-%m', started_at) AS month, COUNT(DISTINCT user_id) AS dau
    FROM conversations GROUP BY day, month
),
monthly AS (
    SELECT strftime('%Y-%m', started_at) AS month, COUNT(DISTINCT user_id) AS mau
    FROM conversations GROUP BY month
)
SELECT
    d.month,
    ROUND(AVG(d.dau), 1) AS avg_dau,
    m.mau,
    ROUND(100.0 * AVG(d.dau) / m.mau, 1) AS stickiness_pct
FROM daily d
JOIN monthly m ON m.month = d.month
GROUP BY d.month, m.mau
ORDER BY d.month;

-- Q: usage_by_plan
WITH per_user AS (
    SELECT u.plan, u.user_id, COUNT(c.conversation_id) AS n_conv
    FROM users u
    JOIN conversations c ON c.user_id = u.user_id
    GROUP BY u.plan, u.user_id
)
SELECT
    plan,
    COUNT(*)                   AS active_users,
    ROUND(AVG(n_conv), 2)      AS avg_conversations_per_user,
    ROUND(100.0 * AVG(CASE WHEN n_conv >= 3 THEN 1.0 ELSE 0 END), 1) AS pct_power_users_3plus
FROM per_user
GROUP BY plan
ORDER BY avg_conversations_per_user DESC;

-- Q: intent_mix
SELECT
    intent,
    COUNT(*) AS conversations,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_conversations,
    ROUND(AVG(num_turns), 1) AS avg_turns
FROM conversations
GROUP BY intent
ORDER BY conversations DESC;
