-- =====================================================================
-- 05_csat_analysis.sql
-- Customer satisfaction. CSAT is a voluntary 1-5 survey, so ALWAYS check response bias.
-- CSAT % = share of responses scoring 4 or 5.
-- =====================================================================

-- Q: csat_summary
SELECT
    COUNT(*)                                             AS conversations,
    COUNT(csat_score)                                    AS survey_responses,
    ROUND(100.0 * COUNT(csat_score) / COUNT(*), 1)       AS response_rate_pct,
    ROUND(AVG(csat_score), 2)                            AS avg_csat,
    ROUND(100.0 * AVG(CASE WHEN csat_score IS NULL THEN NULL WHEN csat_score >= 4 THEN 1.0 ELSE 0 END), 1) AS csat_pct_satisfied,
    ROUND(100.0 * AVG(CASE WHEN csat_score IS NULL THEN NULL WHEN csat_score <= 2 THEN 1.0 ELSE 0 END), 1) AS pct_dissatisfied
FROM conversations;

-- Q: survey_response_bias
-- Unresolved users respond more often, so raw CSAT is pessimistic compared with the true population.
SELECT
    CASE WHEN resolved = 1 THEN 'resolved' ELSE 'unresolved' END AS outcome,
    COUNT(*) AS conversations,
    ROUND(100.0 * COUNT(csat_score) / COUNT(*), 1) AS response_rate_pct,
    ROUND(AVG(csat_score), 2) AS avg_csat
FROM conversations
GROUP BY outcome;

-- Q: csat_by_intent
SELECT
    intent,
    COUNT(csat_score) AS responses,
    ROUND(AVG(csat_score), 2) AS avg_csat,
    ROUND(100.0 * AVG(CASE WHEN csat_score >= 4 THEN 1.0 ELSE 0 END), 1) AS csat_pct_satisfied,
    RANK() OVER (ORDER BY AVG(csat_score) ASC) AS worst_rank
FROM conversations
WHERE csat_score IS NOT NULL
GROUP BY intent
ORDER BY avg_csat ASC;

-- Q: csat_by_platform_plan
SELECT
    u.platform, u.plan,
    COUNT(c.csat_score) AS responses,
    ROUND(AVG(c.csat_score), 2) AS avg_csat
FROM conversations c
JOIN users u ON u.user_id = c.user_id
WHERE c.csat_score IS NOT NULL
GROUP BY u.platform, u.plan
HAVING COUNT(c.csat_score) >= 50
ORDER BY avg_csat ASC;

-- Q: csat_weekly_trend
WITH weekly AS (
    SELECT
        strftime('%Y-W%W', started_at) AS week,
        COUNT(csat_score) AS responses,
        AVG(csat_score)   AS avg_csat
    FROM conversations
    WHERE csat_score IS NOT NULL
    GROUP BY week
)
SELECT
    week, responses,
    ROUND(avg_csat, 2) AS avg_csat,
    ROUND(avg_csat - LAG(avg_csat) OVER (ORDER BY week), 2) AS wow_change
FROM weekly
ORDER BY week;

-- Q: csat_after_escalation
SELECT
    CASE WHEN escalated_to_human = 1 THEN 'escalated to human' ELSE 'handled by bot' END AS handled_by,
    COUNT(*) AS conversations,
    ROUND(100.0 * AVG(resolved), 1) AS completion_pct,
    ROUND(AVG(csat_score), 2) AS avg_csat
FROM conversations
GROUP BY handled_by;
