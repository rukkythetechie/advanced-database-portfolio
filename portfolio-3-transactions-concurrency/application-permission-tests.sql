-- Corridor Pay: restricted application permission tests
-- Run as the administrator; temporarily switch to the app role.
-- All fixtures and financial changes are rolled back.
\set ON_ERROR_STOP on
BEGIN;

-- Prepare temporary instructions as the administrator.
SELECT
    p.business_id AS test_business,
    p.wallet_id AS ngn_wallet,
    p.beneficiary_id AS test_beneficiary,
    p.initiated_by AS test_actor
FROM payment p
JOIN ledger_transaction t ON t.payment_id = p.payment_id
WHERE t.description = 'Concurrency test A'
  AND p.status = 'processing'
\gset

SELECT ledger_account_id AS clearing_account
FROM ledger_account
WHERE account_name = 'Concurrency Test NGN Clearing'
  AND account_type = 'liability'
  AND currency_code = 'NGN'
  AND wallet_id IS NULL
\gset

SELECT ledger_account_id AS cash_account
FROM ledger_account
WHERE account_name = 'Ledger Test NGN Cash'
  AND account_type = 'asset'
  AND currency_code = 'NGN'
  AND wallet_id IS NULL
\gset

INSERT INTO payment (
    business_id, wallet_id, beneficiary_id,
    initiated_by, amount
)
VALUES (
    :test_business, :ngn_wallet, :test_beneficiary,
    :test_actor, 5000.00
)
RETURNING payment_id AS permission_payment
\gset

INSERT INTO payment_status_history (
    payment_id, to_status, actor_type, changed_by, reason
)
VALUES (
    :permission_payment, 'pending', 'user', :test_actor,
    'Temporary instruction for application permission tests'
);

INSERT INTO wallet (business_id, currency_code)
VALUES (:test_business, 'USD')
RETURNING wallet_id AS usd_wallet
\gset

INSERT INTO ledger_account (
    account_name, account_type, currency_code, wallet_id
)
VALUES (
    'Permission Test USD Wallet', 'liability', 'USD', :usd_wallet
);

INSERT INTO ledger_account (
    account_name, account_type, currency_code
)
VALUES ('Permission Test USD FX Asset', 'asset', 'USD')
RETURNING ledger_account_id AS usd_fx_account
\gset

INSERT INTO fx_quote (
    business_id, source_currency, target_currency,
    source_amount, exchange_rate, expires_at
)
VALUES (
    :test_business, 'NGN', 'USD',
    1000.00, 0.000750000000,
    clock_timestamp() + INTERVAL '1 hour'
)
RETURNING quote_id AS permission_quote
\gset


-- Act as the restricted backend role.
SET LOCAL ROLE corridor_p3_app;

SELECT current_user AS testing_role;

DO $$
DECLARE
    v_test RECORD;
    v_rejected BOOLEAN;
BEGIN
    IF current_user <> 'corridor_p3_app' THEN
        RAISE EXCEPTION 'TEST FAILED: wrong database role';
    END IF;

    IF pg_has_role(
        current_user, 'corridor_p3_routine_owner', 'MEMBER'
    ) THEN
        RAISE EXCEPTION 'TEST FAILED: app can assume the routine owner';
    END IF;

    FOR v_test IN
        SELECT *
        FROM (
            VALUES
                (
                    'direct wallet update',
                    'UPDATE public.wallet SET balance = 0 WHERE FALSE'
                ),
                (
                    'direct payment status update',
                    'UPDATE public.payment SET status = ''completed'' WHERE FALSE'
                ),
                (
                    'direct ledger transaction insert',
                    'INSERT INTO public.ledger_transaction (transaction_type, description) VALUES (''funding'', ''Forbidden app posting'')'
                ),
                (
                    'audit deletion',
                    'DELETE FROM public.audit_event WHERE FALSE'
                ),
                (
                    'payment history deletion',
                    'DELETE FROM public.payment_status_history WHERE FALSE'
                ),
                (
                    'direct quote update',
                    'UPDATE public.fx_quote SET exchange_rate = 1 WHERE FALSE'
                ),
                (
                    'raw ledger posting routine',
                    'SELECT public.post_ledger_transaction(1::BIGINT)'
                ),
                (
                    'object creation in public schema',
                    'CREATE TABLE public.forbidden_app_table (id INTEGER)'
                )
        ) AS cases(label, command)
    LOOP
        v_rejected := FALSE;

        BEGIN
            EXECUTE v_test.command;
        EXCEPTION WHEN insufficient_privilege THEN
            v_rejected := TRUE;
        END;

        IF NOT v_rejected THEN
            RAISE EXCEPTION 'TEST FAILED: app allowed %', v_test.label;
        END IF;

        RAISE NOTICE 'PASS: app denied %', v_test.label;
    END LOOP;
END;
$$;


-- All four controlled entry points must still work.
SELECT public.process_payment(
    :permission_payment, :test_actor, :clearing_account
) AS processing_transaction;

SELECT public.settle_payment(
    :permission_payment, :test_actor, :cash_account
) AS settlement_transaction;

SELECT public.reverse_payment(
    :permission_payment, :test_actor,
    'Simulated refund during application permission testing'
) AS reversal_transaction;

-- The payment and refund above have a net zero wallet effect.
-- Convert NGN 1000.00 to USD 0.75.
SELECT public.execute_fx_quote(
    :permission_quote, :ngn_wallet, :usd_wallet,
    :test_actor, :cash_account, :usd_fx_account
) AS conversion_id;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.wallet w
        JOIN public.business b ON b.business_id = w.business_id
        WHERE b.country_code = 'NG'
          AND b.registration_number = 'P3-LEDGER-001'
          AND w.currency_code = 'NGN'
          AND w.balance = 29000.00
    ) OR NOT EXISTS (
        SELECT 1
        FROM public.wallet w
        JOIN public.business b ON b.business_id = w.business_id
        WHERE b.country_code = 'NG'
          AND b.registration_number = 'P3-LEDGER-001'
          AND w.currency_code = 'USD'
          AND w.balance = 0.75
    ) THEN
        RAISE EXCEPTION 'TEST FAILED: app routine wallet balances';
    END IF;

    RAISE NOTICE
        'PASS: all four controlled routines executed as the restricted app role';
END;
$$;

SELECT
    current_user AS testing_role,
    p.status AS refunded_payment_status,
    w.balance AS ngn_balance_after_conversion
FROM public.payment p
JOIN public.wallet w ON w.wallet_id = p.wallet_id
WHERE p.payment_id = :permission_payment;

RESET ROLE;
ROLLBACK;

-- Expect NGN 30000.00 and no temporary USD wallet.
SELECT w.currency_code, w.balance
FROM wallet w
JOIN business b ON b.business_id = w.business_id
WHERE b.country_code = 'NG'
  AND b.registration_number = 'P3-LEDGER-001'
ORDER BY w.currency_code;