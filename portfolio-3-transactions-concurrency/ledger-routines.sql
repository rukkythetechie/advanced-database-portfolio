-- Corridor Pay: ledger routines and protections
-- Portfolio 3; run against corridorpay_p3.

-- Transactions must start as drafts.
-- Once posted, they cannot be changed or deleted.
CREATE OR REPLACE FUNCTION guard_ledger_transaction()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'draft' THEN
            RAISE EXCEPTION
                'A ledger transaction must be created as a draft';
        END IF;

        RETURN NEW;
    END IF;

    IF OLD.status = 'posted' THEN
        RAISE EXCEPTION
            'Posted ledger transactions cannot be changed or deleted';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    IF NEW.ledger_transaction_id
        IS DISTINCT FROM OLD.ledger_transaction_id THEN
        RAISE EXCEPTION
            'A ledger transaction ID cannot be changed';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER ledger_transaction_guard
BEFORE INSERT OR UPDATE OR DELETE ON ledger_transaction
FOR EACH ROW
EXECUTE FUNCTION guard_ledger_transaction();


-- Entries can change only while their parent is a draft.
CREATE OR REPLACE FUNCTION guard_ledger_entry()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_transaction_id BIGINT;
    v_status TEXT;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.ledger_transaction_id
            IS DISTINCT FROM OLD.ledger_transaction_id THEN
            RAISE EXCEPTION
                'An entry cannot move to another ledger transaction';
        END IF;
    END IF;

    IF TG_OP = 'DELETE' THEN
        v_transaction_id := OLD.ledger_transaction_id;
    ELSE
        v_transaction_id := NEW.ledger_transaction_id;
    END IF;

    SELECT status
    INTO v_status
    FROM ledger_transaction
    WHERE ledger_transaction_id = v_transaction_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ledger transaction does not exist';
    END IF;

    IF v_status <> 'draft' THEN
        RAISE EXCEPTION
            'Entries of a posted transaction cannot be changed';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER ledger_entry_guard
BEFORE INSERT OR UPDATE OR DELETE ON ledger_entry
FOR EACH ROW
EXECUTE FUNCTION guard_ledger_entry();

-- Validate a draft and update wallet balances when it is posted.
CREATE OR REPLACE FUNCTION apply_ledger_posting()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_wallet RECORD;
    v_change NUMERIC;
BEGIN
    -- Entry edits lock this same transaction row.
    -- The UPDATE that triggered this function already holds its lock.

    IF (
        SELECT COUNT(*)
        FROM ledger_entry
        WHERE ledger_transaction_id = NEW.ledger_transaction_id
    ) < 2 THEN
        RAISE EXCEPTION
            'Posting requires at least two ledger entries';
    END IF;

    -- Keep account properties stable during validation and posting.
    PERFORM a.ledger_account_id
    FROM ledger_account AS a
    WHERE EXISTS (
        SELECT 1
        FROM ledger_entry AS e
        WHERE e.ledger_account_id = a.ledger_account_id
          AND e.ledger_transaction_id = NEW.ledger_transaction_id
    )
    ORDER BY a.ledger_account_id
    FOR SHARE OF a;

    -- Debits must equal credits within every currency.
    IF EXISTS (
        SELECT a.currency_code
        FROM ledger_entry AS e
        JOIN ledger_account AS a
            ON a.ledger_account_id = e.ledger_account_id
        WHERE e.ledger_transaction_id = NEW.ledger_transaction_id
        GROUP BY a.currency_code
        HAVING SUM(
            CASE e.entry_type
                WHEN 'debit' THEN e.amount
                ELSE -e.amount
            END
        ) <> 0
    ) THEN
        RAISE EXCEPTION
            'Debits and credits must balance within each currency';
    END IF;

    -- Lock all affected wallets in a consistent order.
    PERFORM w.wallet_id
    FROM wallet AS w
    WHERE EXISTS (
        SELECT 1
        FROM ledger_account AS a
        JOIN ledger_entry AS e
            ON e.ledger_account_id = a.ledger_account_id
        WHERE a.wallet_id = w.wallet_id
          AND e.ledger_transaction_id = NEW.ledger_transaction_id
    )
    ORDER BY w.wallet_id
    FOR NO KEY UPDATE OF w;

    -- A wallet account must be a liability in its wallet's currency.
    IF EXISTS (
        SELECT 1
        FROM ledger_entry AS e
        JOIN ledger_account AS a
            ON a.ledger_account_id = e.ledger_account_id
        JOIN wallet AS w
            ON w.wallet_id = a.wallet_id
        WHERE e.ledger_transaction_id = NEW.ledger_transaction_id
          AND (
              a.account_type <> 'liability'
              OR a.currency_code <> w.currency_code
          )
    ) THEN
        RAISE EXCEPTION
            'Wallet ledger account type or currency is invalid';
    END IF;

    -- Wallet liability balance increases with credits
    -- and decreases with debits.
    FOR v_wallet IN
        SELECT w.wallet_id, w.balance
        FROM wallet AS w
        WHERE EXISTS (
            SELECT 1
            FROM ledger_account AS a
            JOIN ledger_entry AS e
                ON e.ledger_account_id = a.ledger_account_id
            WHERE a.wallet_id = w.wallet_id
              AND e.ledger_transaction_id = NEW.ledger_transaction_id
        )
        ORDER BY w.wallet_id
    LOOP
        SELECT SUM(
            CASE e.entry_type
                WHEN 'credit' THEN e.amount
                ELSE -e.amount
            END
        )
        INTO v_change
        FROM ledger_entry AS e
        JOIN ledger_account AS a
            ON a.ledger_account_id = e.ledger_account_id
        WHERE e.ledger_transaction_id = NEW.ledger_transaction_id
          AND a.wallet_id = v_wallet.wallet_id;

        IF v_wallet.balance = 'NaN'::NUMERIC
           OR v_wallet.balance + v_change < 0 THEN
            RAISE EXCEPTION
                'Wallet % has an invalid or insufficient balance',
                v_wallet.wallet_id;
        END IF;

        UPDATE wallet
        SET balance = balance + v_change
        WHERE wallet_id = v_wallet.wallet_id;
    END LOOP;

    RETURN NEW;
END;
$$;

CREATE TRIGGER ledger_transaction_post
BEFORE UPDATE OF status ON ledger_transaction
FOR EACH ROW
WHEN (OLD.status = 'draft' AND NEW.status = 'posted')
EXECUTE FUNCTION apply_ledger_posting();


-- Entry point for posting a draft transaction.
CREATE OR REPLACE FUNCTION post_ledger_transaction(
    p_transaction_id BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_status TEXT;
BEGIN
    SELECT status
    INTO v_status
    FROM ledger_transaction
    WHERE ledger_transaction_id = p_transaction_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ledger transaction does not exist';
    END IF;

    IF v_status <> 'draft' THEN
        RAISE EXCEPTION 'Ledger transaction has already been posted';
    END IF;

    UPDATE ledger_transaction
    SET status = 'posted',
        posted_at = clock_timestamp()
    WHERE ledger_transaction_id = p_transaction_id;
END;
$$;

-- Protect the accounting properties of ledger accounts.
CREATE OR REPLACE FUNCTION guard_ledger_account()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_currency TEXT;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.ledger_account_id
            IS DISTINCT FROM OLD.ledger_account_id THEN
            RAISE EXCEPTION 'A ledger account ID cannot be changed';
        END IF;

        IF ROW(NEW.account_type, NEW.currency_code, NEW.wallet_id)
            IS DISTINCT FROM
            ROW(OLD.account_type, OLD.currency_code, OLD.wallet_id)
        THEN
            IF EXISTS (
                SELECT 1
                FROM ledger_entry AS e
                JOIN ledger_transaction AS t
                    ON t.ledger_transaction_id =
                       e.ledger_transaction_id
                WHERE e.ledger_account_id = OLD.ledger_account_id
                  AND t.status = 'posted'
            ) THEN
                RAISE EXCEPTION
                    'Account properties cannot change after posting';
            END IF;
        END IF;
    END IF;

    IF NEW.wallet_id IS NOT NULL THEN
        SELECT currency_code
        INTO v_currency
        FROM wallet
        WHERE wallet_id = NEW.wallet_id
        FOR KEY SHARE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'The linked wallet does not exist';
        END IF;

        IF NEW.account_type <> 'liability'
           OR NEW.currency_code <> v_currency THEN
            RAISE EXCEPTION
                'A wallet account must be a matching-currency liability';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER ledger_account_guard
BEFORE INSERT OR UPDATE ON ledger_account
FOR EACH ROW
EXECUTE FUNCTION guard_ledger_account();


-- Wallet ownership and currency remain fixed after creation.
-- Opening funds must be recorded through ledger posting.
CREATE OR REPLACE FUNCTION guard_wallet_structure()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.balance <> 0 THEN
            RAISE EXCEPTION 'A new wallet must start at zero';
        END IF;
    ELSE
        IF ROW(NEW.wallet_id, NEW.business_id, NEW.currency_code)
            IS DISTINCT FROM
            ROW(OLD.wallet_id, OLD.business_id, OLD.currency_code)
        THEN
            RAISE EXCEPTION
                'Wallet identity, ownership and currency cannot change';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER wallet_structure_guard
BEFORE INSERT OR UPDATE ON wallet
FOR EACH ROW
EXECUTE FUNCTION guard_wallet_structure();


-- PostgreSQL numeric supports NaN; exclude it explicitly.
ALTER TABLE wallet
    ADD CONSTRAINT wallet_balance_not_nan_check
    CHECK (balance <> 'NaN'::NUMERIC);