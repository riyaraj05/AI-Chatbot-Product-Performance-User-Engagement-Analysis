-- =====================================================================
-- 01_data_quality_checks.sql
-- Validate the data before computing any product metric.
-- =====================================================================

-- Q: row_counts
SELECT 'users' AS table_name, COUNT(*) AS n_rows FROM users
UNION ALL SELECT 'conversations', COUNT(*) FROM conversations
UNION ALL SELECT 'feedback',      COUNT(*) FROM feedback;

-- Q: date_range
SELECT
    (SELECT MIN(started_at) FROM conversations) AS first_conversation,
    (SELECT MAX(started_at) FROM conversations) AS last_conversation,
    (SELECT MIN(signup_date) FROM users)        AS first_signup,
    (SELECT MAX(signup_date) FROM users)        AS last_signup;

-- Q: invalid_values
-- Every count below should be 0.
SELECT
    SUM(CASE WHEN avg_response_latency_ms <= 0 THEN 1 ELSE 0 END)                AS non_positive_latency,
    SUM(CASE WHEN csat_score IS NOT NULL AND csat_score NOT BETWEEN 1 AND 5 THEN 1 ELSE 0 END) AS csat_out_of_range,
    SUM(CASE WHEN resolved NOT IN (0, 1) THEN 1 ELSE 0 END)                       AS bad_resolved_flag,
    SUM(CASE WHEN num_turns < 1 THEN 1 ELSE 0 END)                                AS zero_turn_conversations
FROM conversations;

-- Q: conversations_before_signup
-- A conversation cannot start before the user signed up. Expect 0.
SELECT COUNT(*) AS conversations_before_signup
FROM conversations c
JOIN users u ON u.user_id = c.user_id
WHERE date(c.started_at) < u.signup_date;

-- Q: orphan_records
SELECT
    (SELECT COUNT(*) FROM conversations c LEFT JOIN users u ON u.user_id = c.user_id WHERE u.user_id IS NULL) AS conversations_without_user,
    (SELECT COUNT(*) FROM feedback f LEFT JOIN conversations c ON c.conversation_id = f.conversation_id WHERE c.conversation_id IS NULL) AS feedback_without_conversation;

-- Q: missing_data
-- CSAT is a voluntary survey, so many NULLs are expected. This is survey non-response, not an error.
SELECT
    COUNT(*) AS conversations,
    SUM(CASE WHEN csat_score IS NULL THEN 1 ELSE 0 END) AS csat_missing,
    ROUND(100.0 * SUM(CASE WHEN csat_score IS NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS csat_missing_pct
FROM conversations;
