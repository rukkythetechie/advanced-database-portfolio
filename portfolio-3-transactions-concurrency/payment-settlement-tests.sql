-- Corridor Pay: simulated settlement tests
-- Requires the committed concurrency demonstration.
-- All settlement changes are rolled back.
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_payment_id BIGINT;
    v_actor_id BIGINT;
    v_wallet_id BIGINT;
    v_wallet_account_id BIGINT;
    v_cash_id BIGINT;
    v_settlement_id BIGINT;
    v_original_balance NUMERIC;
    v_rejected BOOLEAN;
BEGIN
    SELECT p.payment_id, p.initiated_by, p.wallet_id,
           a.ledger_account_id, w.balance
    INTO v_payment_id, v_actor_id, v_wallet_id,
         v_wallet_account_id, v_original_balance
    FROM payment p
    JOIN ledger_transaction t ON t.payment_id = p.payment_id
    JOIN wallet w ON w.wallet_id = p.wallet_id
    JOIN ledger_account a ON a.wallet_id = w.wallet_id
    WHERE t.description = 'Concurrency test A'
      AND t.status = 'posted'
      AND p.status = 'processing';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Processing payment A fixture was not found';
    END IF;

    SELECT ledger_account_id
    INTO v_cash_id
    FROM ledger_account
    WHERE account_name = 'Ledger Test NGN Cash'
      AND account_type = 'asset'
      AND currency_code = 'NGN'
      AND wallet_id IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Test cash account was not found';
    END IF;

    -- 1. A wallet liability cannot be used as platform cash.
    v_rejected := FALSE;
    BEGIN
        PERFORM settle_payment(
            v_payment_id, v_actor_id, v_wallet_account_id
        );
    EXCEPTION WHEN raise_exception THEN
        IF POSITION(
            'Settlement requires a platform cash asset account'
            IN SQLERRM
        ) = 0 THEN
            RAISE;
        END IF;
        v_rejected := TRUE;
    END;

    IF NOT v_rejected THEN
        RAISE EXCEPTION 'TEST FAILED: invalid cash account accepted';
    END IF;

    RAISE NOTICE 'PASS: invalid settlement cash account rejected';

    -- 2. Valid simulated settlement.
    v_settlement_id := settle_payment(
        v_payment_id, v_actor_id, v_cash_id
    );

    IF NOT EXISTS (
        SELECT 1
        FROM payment p
        JOIN ledger_transaction t ON t.payment_id = p.payment_id
        WHERE p.payment_id = v_payment_id
          AND p.status = 'completed'
          AND p.completed_at IS NOT NULL
          AND t.ledger_transaction_id = v_settlement_id
          AND t.transaction_type = 'payout_settlement'
          AND t.status = 'posted'
    ) THEN
        RAISE EXCEPTION 'TEST FAILED: settlement state or timestamp';
    END IF;

    IF (
        SELECT balance FROM wallet WHERE wallet_id = v_wallet_id
    ) IS DISTINCT FROM v_original_balance THEN
        RAISE EXCEPTION 'TEST FAILED: settlement debited wallet again';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM ledger_entry
        WHERE ledger_transaction_id = v_settlement_id
    ) <> 2 OR (
        SELECT SUM(
            CASE entry_type
                WHEN 'debit' THEN amount
                ELSE -amount
            END
        )
        FROM ledger_entry
        WHERE ledger_transaction_id = v_settlement_id
    ) IS DISTINCT FROM 0::NUMERIC THEN
        RAISE EXCEPTION 'TEST FAILED: settlement entries';
    END IF;

    RAISE NOTICE 'PASS: settlement posted without a second wallet debit';

    -- 3. History and audit belong to this settlement.
    IF (
        SELECT COUNT(*)
        FROM payment_status_history
        WHERE payment_id = v_payment_id
          AND from_status = 'processing'
          AND to_status = 'completed'
          AND ledger_transaction_id = v_settlement_id
          AND changed_by = v_actor_id
    ) <> 1 OR (
        SELECT COUNT(*)
        FROM audit_event
        WHERE action = 'settle_payment'
          AND entity_type = 'payment'
          AND entity_id = v_payment_id
          AND outcome = 'success'
          AND details ->> 'ledger_transaction_id'
              = v_settlement_id::TEXT
    ) <> 1 THEN
        RAISE EXCEPTION 'TEST FAILED: settlement history or audit';
    END IF;

    RAISE NOTICE 'PASS: completion history and success audit saved';

    -- 4. Completed payment cannot settle again.
    v_rejected := FALSE;
    BEGIN
        PERFORM settle_payment(
            v_payment_id, v_actor_id, v_cash_id
        );
    EXCEPTION WHEN raise_exception THEN
        IF POSITION(
            'Only a processing payment can be settled' IN SQLERRM
        ) = 0 THEN
            RAISE;
        END IF;
        v_rejected := TRUE;
    END;

    IF NOT v_rejected THEN
        RAISE EXCEPTION 'TEST FAILED: duplicate settlement accepted';
    END IF;

    RAISE NOTICE 'PASS: duplicate settlement rejected';
END;
$$;

-- Show the temporary completed state.
SELECT
    p.status AS payment_status,
    p.completed_at IS NOT NULL AS completion_time_recorded,
    t.status AS settlement_status,
    w.balance AS wallet_balance
FROM payment p
JOIN wallet w ON w.wallet_id = p.wallet_id
JOIN ledger_transaction t ON t.payment_id = p.payment_id
WHERE t.transaction_type = 'payout_settlement'
  AND p.payment_id = (
      SELECT payment_id
      FROM ledger_transaction
      WHERE description = 'Concurrency test A'
  );

ROLLBACK;

-- Expect processing, 30000.00 and zero settlement transactions.
SELECT
    p.status AS restored_payment_status,
    w.balance AS wallet_balance,
    (
        SELECT COUNT(*)
        FROM ledger_transaction s
        WHERE s.payment_id = p.payment_id
          AND s.transaction_type = 'payout_settlement'
    ) AS settlement_transactions_remaining
FROM payment p
JOIN wallet w ON w.wallet_id = p.wallet_id
JOIN ledger_transaction t ON t.payment_id = p.payment_id
WHERE t.description = 'Concurrency test A';