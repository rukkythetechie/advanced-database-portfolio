-- Support filtering by business and status,
-- followed by newest payments first.
CREATE INDEX payment_business_status_recent_idx
ON payment (
    business_id,
    status,
    created_at DESC,
    payment_id DESC
);

-- Support payment-history lookups in event order.
CREATE INDEX payment_history_payment_time_idx
ON payment_status_history (
    payment_id,
    changed_at,
    history_id
);