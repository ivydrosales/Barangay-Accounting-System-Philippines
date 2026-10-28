# Prompts to give Claude Code, in order

> **Status (28 Oct 2026):** Prompts 1 to 5 are done; Phase 0 and Phase 1 are built and tested (see README.md). Next: run one month in parallel with paper (the Phase 1 gate), then Phase 2.

Paste one at a time. Wait for each to finish and read the summary before moving on. You do not need to understand the code; you need to confirm that what it describes matches the manual and the proposal.

## Prompt 1 — orientation (no code yet)

> Read CLAUDE.md and docs/PROPOSAL.md completely. Then open docs/coa_manual_extracted_text.txt and skim Chapters I–XII. Give me, in plain language, a one-page summary of what we are building, the five riskiest parts, and any place where the proposal and the manual disagree. Do not write code yet.

## Prompt 2 — Phase 0: project skeleton and database

> Set up the project for Phase 0 as described in docs/PROPOSAL.md section 8 and 10: a Next.js (TypeScript) app with Supabase. Create the database migrations for master data (lgu, barangay, official, fund, account, bank_account, supplier, employee, accountable_form), the journal (journal_entry, journal_line, period) and audit_log, with row-level security so a barangay user sees only their barangay and an LGU accountant sees all barangays of their LGU. Load data/chart_of_accounts.csv as seed data. Add database-level rules: entries must balance, accounts must exist in the chart, closed periods cannot be changed. Write tests for those rules. Explain to me how to create the Supabase project and where to paste the keys.

## Prompt 3 — Phase 1: Official Receipts, RCD and Cashbook

> Build the collections screens for Phase 1: Official Receipt issuance with serial-number control (one series per OR booklet, cancelled ORs kept), Report of Collections and Remittances (Annex 9.1) for deputized collectors, Report of Collections and Deposits (Annex 9) generated from the day's ORs and deposits, and the Cashbook (Annex 8) with its four sections and daily balances. Read each annex's instructions in docs/coa_manual_extracted_text.txt first and reproduce every field. Produce the printable PDF of each form in the annex layout. Show me screenshots or a walkthrough of a sample day.

## Prompt 4 — Phase 1: Disbursement Voucher workflow

> Build the Disbursement Voucher (Annex 12) workflow with Boxes A–E as approval steps for the CCA, Barangay Treasurer, Punong Barangay, payee and bookkeeper/accountant; the check register; the Punong Barangay Certification printout; and the Transmittal Letter (Annex 16) that lists the month's paid DVs, RCDs and other reports. A DV must not be payable until Boxes A, B and C are signed. Generate the JCT entries from paid DVs using the pro-forma entries in Chapter V of the manual.

## Prompt 5 — Phase 1 gate check

> We are going to run one month in parallel with paper books in the pilot barangay. Prepare a checklist of what the treasurer should enter each day, what the accountant should compare at month-end, and a report that shows totals per the system vs. totals I type in from the paper Cashbook so we can see any difference.

Then continue with Phase 2 (RAO, SAOB, RSTF, JCT/GJ/GL/SL printouts, bank memos and reconciliation), Phase 3, Phase 4 and Phase 5 as listed in docs/PROPOSAL.md section 10, one form or report at a time, always asking Claude Code to read the annex instructions first.
