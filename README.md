# Advanced Database Systems Portfolio — MIT 8103

**Student:** Yaro Rukayat
**Case study:** Corridor Pay (fictional cross-border B2B payments platform)

## 1. Case Study Statement

**Organisation.** Corridor Pay is a fictional fintech company. It helps small and mid-sized businesses pay suppliers across borders. It operates in Nigeria, Canada, the United Kingdom and the United States.

**Nature of the business.** Businesses sign up, pass KYB (Know Your Business) checks, and hold balances in several currencies. They convert between currencies at a quoted FX rate and send payouts to overseas beneficiaries. Corridor Pay settles payouts through local payment partners in each country.

**Users of the database.**
- Business customers — admins and finance staff who fund wallets and send payouts.
- Compliance analysts — review KYB documents and flag risky activity.
- Operations and treasury staff — monitor payouts, handle failures, reconcile balances.
- Payment partners and internal services — update payout status through APIs.

**Major data stored.**
- Businesses, their users and roles
- KYB applications and documents
- Multi-currency wallets
- FX quotes and conversions
- Beneficiaries (payout recipients)
- Transfers and payouts with status history
- Double-entry ledger entries
- Audit logs

**Key operations.**
- Onboard a business and review its KYB
- Fund a wallet
- Convert currency at a locked FX quote
- Send a payout to a beneficiary
- Reverse a failed payout and restore the balance
- Reconcile wallet balances against the ledger

## 2. Repository Structure

```
advanced-database-portfolio/
├── portfolio-1-database-design/
├── portfolio-2-query-optimisation/
├── portfolio-3-transactions-concurrency/
├── portfolio-4-nosql/
├── portfolio-5-distributed-cloud/
├── docker-compose.yml
└── README.md
```

## 3. How to Run

Requires Docker Desktop.

```
docker compose up -d
docker exec -it corridor-pg psql -U corridor -d corridorpay
```

## 4. AI Use Declaration

_To be completed at submission._
