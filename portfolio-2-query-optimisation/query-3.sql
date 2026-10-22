-- Query 3: Pending payment totals by currency.
SELECT
    w.currency_code,
    COUNT(*) AS payment_count,
    SUM(p.amount) AS total_pending_amount
FROM payment AS p
JOIN wallet AS w
    ON w.wallet_id = p.wallet_id
WHERE p.status = 'pending'
GROUP BY w.currency_code
ORDER BY w.currency_code;

-- Measure how PostgreSQL runs this report.
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    w.currency_code,
    COUNT(*) AS payment_count,
    SUM(p.amount) AS total_pending_amount
FROM payment AS p
JOIN wallet AS w
    ON w.wallet_id = p.wallet_id
WHERE p.status = 'pending'
GROUP BY w.currency_code
ORDER BY w.currency_code;