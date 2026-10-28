# Barangay Digital Accounting System

A multi-tenant web app that implements the COA **Manual on the Financial Management of Barangays** (Philippines, 2018 ed., PPSAS-aligned) end to end: budget control, collections, disbursements, cash advances, petty cash, inventory, property (PPE), biological assets, special trust funds, the four books of accounts, and all year-end financial statements — printed in the manual's own annex layouts.

The product owner (Ivy) is **not a developer**. Explain choices in plain language, keep the architecture simple, and never assume she will edit code by hand. Prefer one obvious way to do each thing.

## Source of truth

1. `docs/COA_Manual_Financial_Management_of_Barangays_2018.pdf` — the manual (288 pages). `docs/coa_manual_extracted_text.txt` is its searchable text (page breaks are form feeds; Chapter XIII Chart of Accounts starts near line 3870; Annex instructions start near line 6806).
2. `docs/PROPOSAL.md` — the study of the manual and the build plan. Read it fully before any design work. Section 3 = chart of accounts, 4 = books, 5 = the 43 annex forms, 6 = reports, 7 = transaction flows and posting rules, 8 = architecture and data model, 10 = phased plan.
3. `data/chart_of_accounts.csv` — all 280 COA account codes (verified code-for-code against the manual). Load it as seed data; never invent accounts.

When the manual and this file disagree, the manual wins. When something is not in the manual, flag it as a product decision for Ivy rather than guessing.

## Key domain facts (do not get these wrong)

- Barangays do **not** keep their own books. The Barangay Treasurer (BT) and Chairman of the Committee on Appropriations (CCA) keep source records (Cashbook, RAO, RSTF, stock/property cards) and submit monthly reports; the **City/Municipal (C/M) Accountant** keeps the Journal of Cash Transactions (JCT), General Journal (GJ), General Ledger (GL) and Subsidiary Ledgers (SL) for every barangay in the LGU and prepares the financial statements.
- A **tenant** is a city/municipality; barangays belong to it. Row-level security: barangay users see only their barangay; the Accountant sees all barangays of the LGU; COA auditors are read-only.
- Fiscal year = calendar year. Double-entry. Cash transactions → JCT; non-cash → GJ through an approved Journal Voucher (JV).
- Funds: General Fund, 10% SK, 5% LDRRMF, 20% Development Fund, continuing appropriations, and one Special Trust Fund (STF) per purpose. Every posting carries a fund.
- Obligations may never exceed available appropriations (RAO) or the STF balance (RSTF). The CCA certifies Box A on every PO, DV and Payroll.
- Disbursement Voucher boxes: A = CCA (appropriation), B = BT (funds available, documents complete), C = PB (approve), D = payee receipt, E = accounting entry (Bookkeeper prepares, Accountant approves). Nothing is paid without A, B, C.
- Cash advances: payroll liquidated within 5 days, local travel 30 days, foreign travel 60 days, special purpose on completion; no new advance while one is unliquidated.
- Petty cash: imprest, ≤ 20% of available funds, replenish at 75% used, closed at year-end and on change of custodian; direct purchases ≤ ₱1,000.
- Inventory: moving-average cost. PPE: straight-line depreciation, 5% residual value, from the month the asset is available for use. Infrastructure is PPE. Biological assets at fair value less cost to sell.
- Document numbers: `YYYY-MM-serial`, one series per year (SSMI: per month). The system issues numbers; no gaps, no duplicates, no edits after posting.
- Closed periods are immutable; corrections go through a JV in an open period.
- Deadlines: RCD to Accountant by the 5th; DVs/LR/RAAF/TL within 10 days after month-end; Accountant to COA by the 15th working day; Bank Reconciliation by the 20th; monthly Statement of Receipts and Expenditures within 30 days; year-end FS within 60 days (4 copies); property/supplies inventory reports by 10 January.

## Stack

- **Database/auth:** Supabase (PostgreSQL + Row Level Security). All business rules that must hold (balanced entries, appropriation check, sequential numbers, period lock) are enforced in the database (constraints, triggers, RPC functions), not only in the UI.
- **App:** Next.js (App Router, TypeScript), deployed on Vercel. Installable PWA for treasurers; offline capture for OR, Cashbook and RIS with sync.
- **PDF:** server-side rendering of every annex in the manual's layout (React-PDF or Puppeteer). A printed, signed copy is still what COA receives.
- **Exports:** Excel/CSV of ledgers and reports; monthly package to Google Drive.
- Keep dependencies few. No ORM magic that hides SQL; migrations live in `supabase/migrations`.

## Repository layout and commands

- `supabase/migrations/` — numbered SQL files, applied in order. Add a new file for every schema change; never edit an applied one. Phase 0 files: `..01_foundation` (enums, helpers), `..02_master_data` (lgu, barangay, user_membership, access helpers, account, official, fund, bank_account, supplier, employee, accountable_form), `..03_journal` (period, document_sequence, journal_entry, journal_line, posting/reversal functions, ledger views), `..04_audit_and_rls` (audit_log, policies, grants).
- `supabase/seed.sql` is generated from `data/chart_of_accounts.csv` by `npm run seed:gen`. Edit the CSV, never the SQL.
- `supabase/tests/*.sql` — rule tests in plain SQL (`pg_temp.assert`, `pg_temp.expect_error`, `pg_temp.login(user)`), run by `npm run db:test` (`scripts/db-test.sh`) against a throwaway database. Every new database rule gets a test here; CI runs them.
- `src/app/` Next.js App Router pages; `src/lib/supabase/` the three Supabase clients (server, client, middleware). Server Components and Server Actions talk to Supabase with the user's own session, so RLS does the authorization.
- Access helpers for policies: `can_read(lgu_id, barangay_id)`, `can_write(lgu_id, barangay_id)`, `is_lgu_staff(lgu_id)`, `is_lgu_admin(lgu_id)`, `has_barangay_access(id)`. Use them; do not write ad-hoc membership subqueries in policies.
- Posting: entries are inserted as `draft` with their lines, then `post_journal_entry(id)` balances, numbers and stamps them; `reverse_journal_entry(id, date, reason)` corrects; `close_period(barangay, year, month)` locks a month. Document numbers come only from `next_document_number()`.
- `npm run lint && npm run build` must pass before a commit. `.github/workflows/db-migrate.yml` applies migrations to the hosted Supabase project on push to `main` once the secrets in `docs/SETUP.md` exist.

### Phase 0 product decisions made so far (confirm with Ivy / the accountant)

- Serial numbers are padded to four digits (`2026-01-0001`).
- A closed period cannot be reopened, even by the Accountant; corrections are reversing entries in an open period.
- Every new barangay automatically gets the funds GF, SK, LDRRMF, DF (20% Development) and CA (continuing appropriations); STFs are added by hand, one per purpose.
- Entry numbers are taken at posting time, so abandoned drafts leave no gaps.

## Conventions

- One journal-entry table (header + lines) with a `book` flag (JCT/GJ); GL and SL are views/queries over it. Never store ledger balances that can drift from the lines.
- Every table: `lgu_id`, `barangay_id` (where applicable), `fund_id` (where applicable), `created_by`, `created_at`, `updated_at`; every change is written to `audit_log`.
- Name things as the manual does (RCD, RAO, SAOB, RSTF, DV, PCV, SPCD, LR, TL, RAAF, AIR, RIS, ICS, PAR, PEC, PELC, RRPE, IIAR, RIPE, RISM, SSMI, BAPC, QRBA). Spell the full name once in UI help text.
- Use the manual's illustrative accounting entries (Chapters IV–XI) as unit tests for the posting engine.
- Money: integer centavos or `numeric(14,2)`; never floats. Peso sign ₱. Dates in Asia/Manila.
- Before building any screen, read that form's annex instructions in the manual and reproduce every field and signature box.

## Build order

Follow `docs/PROPOSAL.md` section 10: Phase 0 foundation and seed → Phase 1 cash module → Phase 2 budget control and books → Phase 3 payroll, cash advances, petty cash, property → Phase 4 statements and year-end → Phase 5 rollout. Do not start a later phase's features before the earlier phase's gate is met. Start every work session by stating which phase and which annex/form you are working on.
