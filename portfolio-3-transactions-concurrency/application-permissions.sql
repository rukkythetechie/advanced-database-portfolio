-- Corridor Pay: restricted backend application access
-- Install after all ledger, payment and FX routines.
-- Run as the database administrator.
--
-- These are backend database roles, not customer identities.
-- A trusted backend must supply the authenticated business user ID.
-- Authentication and tenant-specific read filtering are outside
-- this demonstration.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'corridor_p3_routine_owner'
    ) THEN
        CREATE ROLE corridor_p3_routine_owner
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
            NOREPLICATION NOBYPASSRLS;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'corridor_p3_app'
    ) THEN
        CREATE ROLE corridor_p3_app
            NOLOGIN NOINHERIT NOSUPERUSER
            NOCREATEDB NOCREATEROLE
            NOREPLICATION NOBYPASSRLS;
    END IF;
END;
$$;

-- Prevent application-created objects in the trusted schema.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM corridor_p3_app;
GRANT USAGE ON SCHEMA public
TO corridor_p3_app, corridor_p3_routine_owner;

-- Remove default public access and any direct application grants.
REVOKE ALL ON ALL TABLES IN SCHEMA public
FROM PUBLIC, corridor_p3_app;

REVOKE ALL ON ALL SEQUENCES IN SCHEMA public
FROM PUBLIC, corridor_p3_app;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public
FROM PUBLIC, corridor_p3_app;

-- Future functions created by this administrator should not
-- automatically be executable by every database role.
ALTER DEFAULT PRIVILEGES
REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- The routine owner receives the permissions needed internally.
GRANT SELECT ON ALL TABLES IN SCHEMA public
TO corridor_p3_routine_owner;

GRANT USAGE ON ALL SEQUENCES IN SCHEMA public
TO corridor_p3_routine_owner;

GRANT INSERT ON
    public.ledger_transaction,
    public.ledger_entry,
    public.payment_status_history,
    public.audit_event,
    public.fx_conversion
TO corridor_p3_routine_owner;

GRANT UPDATE (balance) ON public.wallet
TO corridor_p3_routine_owner;

GRANT UPDATE (status, completed_at) ON public.payment
TO corridor_p3_routine_owner;

GRANT UPDATE (status, posted_at) ON public.ledger_transaction
TO corridor_p3_routine_owner;

-- SELECT FOR UPDATE/SHARE requires UPDATE permission
-- on at least one column of the locked table.
-- These grants are internal; the application does not receive them.
GRANT UPDATE (business_id) ON public.business
TO corridor_p3_routine_owner;

GRANT UPDATE (user_id) ON public.business_user
TO corridor_p3_routine_owner;

GRANT UPDATE (beneficiary_id) ON public.beneficiary
TO corridor_p3_routine_owner;

GRANT UPDATE (quote_id) ON public.fx_quote
TO corridor_p3_routine_owner;

GRANT UPDATE (ledger_account_id) ON public.ledger_account
TO corridor_p3_routine_owner;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public
TO corridor_p3_routine_owner;

-- Pin the search path, including the temporary schema last.
ALTER FUNCTION public.process_payment(BIGINT, BIGINT, BIGINT)
SET search_path = pg_catalog, public, pg_temp;

ALTER FUNCTION public.settle_payment(BIGINT, BIGINT, BIGINT)
SET search_path = pg_catalog, public, pg_temp;

ALTER FUNCTION public.reverse_payment(BIGINT, BIGINT, TEXT)
SET search_path = pg_catalog, public, pg_temp;

ALTER FUNCTION public.execute_fx_quote(
    BIGINT, BIGINT, BIGINT, BIGINT, BIGINT, BIGINT
)
SET search_path = pg_catalog, public, pg_temp;

ALTER FUNCTION public.post_ledger_transaction(BIGINT)
SET search_path = pg_catalog, public, pg_temp;

-- Give the non-login role ownership of only the four entry points.
-- Temporary schema CREATE permission permits ownership transfer.
GRANT CREATE ON SCHEMA public TO corridor_p3_routine_owner;

ALTER FUNCTION public.process_payment(BIGINT, BIGINT, BIGINT)
OWNER TO corridor_p3_routine_owner;

ALTER FUNCTION public.settle_payment(BIGINT, BIGINT, BIGINT)
OWNER TO corridor_p3_routine_owner;

ALTER FUNCTION public.reverse_payment(BIGINT, BIGINT, TEXT)
OWNER TO corridor_p3_routine_owner;

ALTER FUNCTION public.execute_fx_quote(
    BIGINT, BIGINT, BIGINT, BIGINT, BIGINT, BIGINT
)
OWNER TO corridor_p3_routine_owner;

REVOKE CREATE ON SCHEMA public FROM corridor_p3_routine_owner;

ALTER FUNCTION public.process_payment(BIGINT, BIGINT, BIGINT)
SECURITY DEFINER;

ALTER FUNCTION public.settle_payment(BIGINT, BIGINT, BIGINT)
SECURITY DEFINER;

ALTER FUNCTION public.reverse_payment(BIGINT, BIGINT, TEXT)
SECURITY DEFINER;

ALTER FUNCTION public.execute_fx_quote(
    BIGINT, BIGINT, BIGINT, BIGINT, BIGINT, BIGINT
)
SECURITY DEFINER;

-- The backend may read existing results across businesses.
-- This is not a tenant-isolated customer database role.
GRANT SELECT ON ALL TABLES IN SCHEMA public
TO corridor_p3_app;

-- Only these controlled financial operations are exposed.
GRANT EXECUTE ON FUNCTION
    public.process_payment(BIGINT, BIGINT, BIGINT),
    public.settle_payment(BIGINT, BIGINT, BIGINT),
    public.reverse_payment(BIGINT, BIGINT, TEXT),
    public.execute_fx_quote(
        BIGINT, BIGINT, BIGINT, BIGINT, BIGINT, BIGINT
    )
TO corridor_p3_app;