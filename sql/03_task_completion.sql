-- =====================================================================
-- 03_task_completion.sql
-- Task completion (resolved = 1) and why conversations fail.
-- =====================================================================

-- Q: overall_completion
SELECT
    COUNT(*) AS conversations,
    ROUND(100.0 * AVG(resolved), 1)             AS task_completion_pct,
    ROUND(100.0 * AVG(escalated_to_human), 1)   AS escalation_pct,
    ROUND(100.0 * AVG(CASE WHEN fallback_count > 0 THEN 1.0 ELSE 0 END), 1) AS pct_with_fallback,
    ROUND(AVG(avg_response_latency_ms), 0)      AS avg_latency_ms
FROM conversations;

-- Q: completion_by_intent
-- Window functions compare each intent with the overall rate and rank them.
WITH by_intent AS (
    SELECT intent, COUNT(*) AS conversations, AVG(resolved) AS completion
    FROM conversations GROUP BY intent
),
overall AS (SELECT AVG(resolved) AS overall FROM conversations)
SELECT
    b.intent,
    b.conversations,
    ROUND(100.0 * b.completion, 1) AS completion_pct,
    ROUND(100.0 * (b.completion - o.overall), 1) AS vs_overall_pp,
    RANK() OVER (ORDER BY b.completion ASC) AS worst_rank
FROM by_intent b, overall o
ORDER BY completion_pct ASC;

-- Q: completion_by_latency_bucket
SELECT
    CASE
        WHEN avg_response_latency_ms < 1000 THEN '1) <1s'
        WHEN avg_response_latency_ms < 2000 THEN '2) 1-2s'
        WHEN avg_response_latency_ms < 3000 THEN '3) 2-3s'
        WHEN avg_response_latency_ms < 5000 THEN '4) 3-5s'
        ELSE '5) 5s+'
    END AS latency_bucket,
    COUNT(*) AS conversations,
    ROUND(100.0 * AVG(resolved), 1)          AS completion_pct,
    ROUND(100.0 * AVG(escalated_to_human), 1) AS escalation_pct,
    ROUND(AVG(csat_score), 2)                AS avg_csat
FROM conversations
GROUP BY latency_bucket
ORDER BY latency_bucket;

-- Q: completion_by_fallbacks
-- A "fallback" = the bot replied "I didn't understand". More fallbacks, fewer completions?
SELECT
    CASE WHEN fallback_count >= 3 THEN '3+' ELSE CAST(fallback_count AS TEXT) END AS fallbacks,
    COUNT(*) AS conversations,
    ROUND(100.0 * AVG(resolved), 1) AS completion_pct,
    ROUND(AVG(num_turns), 1) AS avg_turns
FROM conversations
GROUP BY fallbacks
ORDER BY fallbacks;

-- Q: failed_vs_successful_profile
SELECT
    CASE WHEN resolved = 1 THEN 'resolved' ELSE 'unresolved' END AS outcome,
    COUNT(*) AS conversations,
    ROUND(AVG(num_turns), 2)               AS avg_turns,
    ROUND(AVG(fallback_count), 2)          AS avg_fallbacks,
    ROUND(AVG(avg_response_latency_ms), 0) AS avg_latency_ms,
    ROUND(AVG(csat_score), 2)              AS avg_csat
FROM conversations
GROUP BY outcome;

-- Q: daily_latency_with_moving_avg
-- 7-day moving average via a window frame. Days far above their moving average are incidents.
WITH daily AS (
    SELECT
        date(started_at) AS day,
        COUNT(*) AS conversations,
        AVG(avg_response_latency_ms) AS avg_latency,
        AVG(resolved) AS completion
    FROM conversations
    GROUP BY day
)
SELECT
    day, conversations,
    ROUND(avg_latency, 0) AS avg_latency_ms,
    ROUND(AVG(avg_latency) OVER (ORDER BY day ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING), 0) AS prev_7d_avg_latency_ms,
    ROUND(100.0 * completion, 1) AS completion_pct
FROM daily
ORDER BY day;

-- Q: weakest_intent_platform_combos
-- Where is the product weakest? (min volume filter avoids noisy small groups)
SELECT
    c.intent, u.platform,
    COUNT(*) AS conversations,
    ROUND(100.0 * AVG(c.resolved), 1) AS completion_pct,
    ROUND(AVG(c.avg_response_latency_ms), 0) AS avg_latency_ms
FROM conversations c
JOIN users u ON u.user_id = c.user_id
GROUP BY c.intent, u.platform
HAVING COUNT(*) >= 200
ORDER BY completion_pct ASC
LIMIT 8;
