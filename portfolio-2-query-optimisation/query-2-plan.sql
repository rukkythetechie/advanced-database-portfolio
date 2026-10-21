-- Query 2: Measure status-history lookup performance.
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    history_id,
    payment_id,
    from_status,
    to_status,
    changed_at,
    actor_type,
    changed_by,
    reason
FROM payment_status_history
WHERE payment_id = 1
ORDER BY changed_at, history_id;