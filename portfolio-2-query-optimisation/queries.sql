-- Query 1: Recent pending payments for one business.
SELECT
    p.payment_id,
    ben.beneficiary_name,
    w.currency_code,
    p.amount,
    p.status,
    p.created_at
FROM payment AS p
JOIN business AS b
    ON b.business_id = p.business_id
JOIN beneficiary AS ben
    ON ben.beneficiary_id = p.beneficiary_id
JOIN wallet AS w
    ON w.wallet_id = p.wallet_id
WHERE b.country_code = 'NG'
    AND b.registration_number = 'P2-0001'
    AND p.status = 'pending'
ORDER BY p.created_at DESC, p.payment_id DESC
LIMIT 20;