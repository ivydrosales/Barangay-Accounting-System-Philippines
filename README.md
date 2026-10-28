# Barangay Accounting System (Philippines)

A web app that keeps the books of Philippine barangays the way the COA **Manual on the Financial Management of Barangays** (2018, PPSAS-aligned) prescribes: budget control, collections, disbursements, cash advances, petty cash, property, special trust funds, the four books of accounts and the year-end financial statements, printed in the manual's own annex layouts.

One city or municipality is a tenant. Its barangays sit under it. Barangay officers capture transactions; the City/Municipal Accountant's office keeps the journals and ledgers for every barangay of the LGU; COA auditors read everything and change nothing.

## Status

**Phase 0 (foundation) is built.** The database holds the master data (LGUs, barangays, officials, funds, bank accounts, suppliers, employees, accountable forms), the 280-account COA chart, the journal (JCT and GJ) with periods and document numbering, an append-only audit trail and row-level security. The app signs users in and shows them what they can see. All 197 database rule checks pass across Phase 0 and Phase 1.

**Phase 1, collections, is built:** Official Receipts issued in serial order from booklets, the collector's Report of Collections and Remittances (Annex 9.1), the Treasurer's Report of Collections and Deposits (Annex 9) with its accounting entries posted to the Journal of Cash Transactions, and the Cashbook (Annex 8), each printable in the manual's layout.

**Phase 1, disbursements, is built:** Disbursement Vouchers (Annex 12) that move through Boxes A (CCA), B (Treasurer) and C (Punong Barangay) before a check can be drawn, the check register with a printable Punong Barangay Certification, Box D on release, posting to the Journal of Cash Transactions, the Transmittal Letter to the Accountant (Annex 16), a screen for OR and check booklets, and the monthly Report of Accountability for Accountable Forms (Annex 18).

**The Phase 1 gate check is ready:** a parallel-run page with the daily and month-end checklist for the pilot barangay, and a report that sets the totals typed in from the paper Cashbook beside the system's own, for the Accountant to sign off. Phase 2 (budget control and the books of accounts) starts once one month has passed this check. The full plan is in `docs/PROPOSAL.md` section 10.

## What is where

| Path | What it is |
| --- | --- |
| `CLAUDE.md` | Standing instructions for Claude Code: domain rules, stack, conventions, build order |
| `docs/SETUP.md` | How to connect Supabase and Vercel and sign in for the first time (for Ivy) |
| `docs/PROPOSAL.md` | The study of the manual and the phased build plan |
| `docs/COA_Manual_Financial_Management_of_Barangays_2018.pdf` | The manual, the source of truth (`docs/coa_manual_extracted_text.txt` is its searchable text) |
| `data/chart_of_accounts.csv` | All 280 COA account codes; the seed is generated from it |
| `supabase/migrations/` | The database, one numbered SQL file per step |
| `supabase/seed.sql` | The chart of accounts as SQL (generated; run `npm run seed:gen` after editing the CSV) |
| `supabase/tests/` | Rule tests: balanced entries, immutable postings, closed periods, numbering, access |
| `supabase/bootstrap/first_lgu.sql` | One-time script that creates the first LGU, its barangays and your admin login |
| `src/app/` | The Next.js app: login, home, Official Receipts, RCR, RCD, Cashbook, DVs, checks, Transmittal Letters, accountable forms, RAAF, parallel run |
| `src/lib/supabase/` | Supabase clients for server, browser and middleware |
| `scripts/` | `db-test.sh` (build a throwaway database and run the tests), `gen-seed.mjs` |
| `.github/workflows/` | CI (lint, build, database tests) and the migration deploy to Supabase |

## Rules the database enforces on its own

Whatever the app does, PostgreSQL refuses to:

- post an entry whose debits and credits differ, or that uses an account outside the chart;
- change or delete a posted entry or any of its lines (corrections are reversing entries);
- write anything into a closed month, or reopen one;
- pay a DV without Boxes A, B and C signed by the CCA, Treasurer and Punong Barangay, or draw two checks on one DV;
- skip, repeat or rewind a serial number of an OR or check booklet;
- issue a duplicate document number (`YYYY-MM-serial`, one series per barangay, book and year);
- give a barangay a second depository bank account, or overlapping OR serial ranges;
- show a barangay user another barangay, or an LGU another LGU;
- let a COA auditor write, or anyone edit the audit log.

## Running it

You need Node.js 22 and, for the database tests, Docker (local Supabase) or any PostgreSQL 15+.

```bash
npm install
cp .env.example .env.local        # paste the Supabase URL and anon key
npm run dev                       # http://localhost:3000

npm run db:start                  # local Supabase (Docker)
npm run db:reset                  # apply migrations + seed to it
npm run db:test                   # throwaway database, all rule tests
npm run lint && npm run build
```

`npm run db:test -- postgresql://user:pass@host:5432/postgres` runs the tests against any other PostgreSQL you can reach as a superuser.

## Things only Ivy can do

- Create the Supabase and Vercel projects and paste the keys (see `docs/SETUP.md`).
- Pick the pilot city/municipality and 2 to 3 barangays, and get the C/M Accountant's agreement to run in parallel with paper for one year.
- Confirm with the COA regional office that the 2018 manual is still in force and collect later circulars.
- Have a government accountant review the chart of accounts, funds and posting rules at the end of each phase.
