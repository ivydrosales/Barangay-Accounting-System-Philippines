# Barangay Digital Accounting System — Build Proposal

Prepared 28 Oct 2026 for Ivy Rosales. Source: COA Manual on the Financial Management of Barangays (Nov 2018 PDF, docs/COA_Manual_Financial_Management_of_Barangays_2018.pdf).

## Executive summary

The COA Manual on the Financial Management of Barangays (2018 ed., aligned to PPSAS) prescribes one complete, closed accounting system: 43 numbered forms (Annexes 1–43), 4 books of accounts, a fixed Chart of Accounts, and 6 year-end financial statements. A digital system that implements it is a **double-entry government fund accounting app** with a budget-control layer (appropriations and obligations), a cash layer (collections, deposits, disbursements, cash advances, petty cash), a property layer (inventories, PPE, biological assets), special trust fund registries, and a reporting layer that prints every annex exactly as the manual lays it out.

The key design fact: the barangay does **not** keep its own books. The Barangay Treasurer (BT) and the Chairman of the Committee on Appropriations (CCA) keep source records (Cashbook, RAO, stock and property cards) and send monthly reports; the **City/Municipal (C/M) Accountant** keeps the journals, ledgers and financial statements for every barangay in the city or municipality. Your app therefore has two kinds of users: barangay-level officers who capture transactions and produce reports, and the C/M Accountant's office which records, reconciles and reports across all barangays. A system that gives both sides one shared database, with the barangay's reports automatically becoming the accountant's journal entries, removes the monthly paper hand-off that the manual was written around.

What you need to build, in order:

1. Master data: barangay profile, officials and signatories, Chart of Accounts (Chapter XIII), fund types (General Fund, SK 10%, LDRRMF 5%, 20% Development Fund, continuing appropriations, Special Trust Funds).
2. Budget module: appropriation ordinance → Record of Appropriations and Obligations (Annex 6), obligation certification on every PO, DV and payroll, monthly SAOB (Annex 7), Record of Estimated and Actual Income (Annex 41).
3. Cash module: Official Receipts → Report of Collections and Deposits (Annex 9), deputized collectors' RCR (Annex 9.1), Cashbook (Annex 8, 8.1), Disbursement Vouchers (Annex 12), Petty Cash (13, 13.1, 17), Payroll (14), Liquidation Reports (15), Transmittal Letters (16), accountable forms (18), bank memos and reconciliation (10, 11).
4. Property module: PR/PO/AIR (23, 24, 27), Stock Cards and RIS (22, 20), ICS (21), PAR and property cards (25, 26, 26.1), inventory reports (29–32), biological assets (42, 43), depreciation (straight-line, 5% residual).
5. Accounting engine: the BT's reports post automatically to the Journal of Cash Transactions and General Journal (Annexes 1, 2), then to General and Subsidiary Ledgers (3, 4); Journal Vouchers (5) for non-cash entries; adjusting and closing entries (Chapter IX); trial balances.
6. Financial statements: Statement of Management Responsibility, Financial Performance, Financial Position, Net Assets/Equity, Cash Flows, Comparison of Budget and Actual Amounts, Notes (Annexes 34–40).

On connectors: no commercial accounting connector (QuickBooks, Xero, etc.) can host this as-is, because the Chart of Accounts, fund segregation, obligation accounting and the annex formats are COA-prescribed and the C/M Accountant's office cannot submit a QuickBooks report to COA. The recommendation in section 9 is to build the ledger yourself (the accounting logic in this manual is small and fixed) and use connectors only at the edges: Google Drive/Sheets for exports and backups, and optionally an accounting package as a secondary ledger for cities that already use one. Section 10 gives a phased, no-code-friendly build plan.

## What the manual covers and what each chapter means for the system

| Chapter | What it prescribes | What the system must do |
| --- | --- | --- |
| I General Accounting Instructions (p.1–5) | Fiscal year Jan–Dec; double-entry; COA Chart of Accounts; 4 books (JCT, GJ, GL, SL); cash vs non-cash split; STF for earmarked funds; monthly bank reconciliation; depreciation straight-line with 5% residual; inventories at weighted average | Core settings and validation rules: every posting must balance, every account must come from the COA chart, every transaction tagged cash or non-cash and by fund |
| II Barangay Accounting Plan (p.6–7) | Workflow: source documents → BT reports → JCT/GJ → GL/SL → trial balance → financial statements | The end-to-end pipeline of the app; defines who does what (BT vs C/M Accountant) |
| III Appropriations and Obligations (p.8–9) | RAO per fund kept by the CCA; obligations may never exceed appropriations; CCA certifies appropriation on PO/DV/Payroll; monthly SAOB; REAI kept by BT | Budget-control module with hard stop when an obligation exceeds the available balance; CCA e-certification step on every spending document |
| IV Collections and Deposits (p.10–17) | Official Receipts in strict sequence; daily intact deposit (or weekly / when ≥ ₱5,000 if bank is far); deputized collectors remit to BT; RCD monthly to accountant by the 5th; bank credit/debit memos; one AGDB account | OR issuance with sequence control, RCD/RCR generation, deposit slip capture, accountable-forms stock control, auto journal entries 4.3.1–4.3.3 |
| V Disbursements (p.18–36) | DV/PCV/Payroll only; checks with Punong Barangay Certification; cash advances (payroll, travel, special purpose) with liquidation deadlines (5 days payroll, 30/60 days travel); petty cash imprest ≤ 20% of funds, replenish at 75%, close at year-end; infrastructure by contract or by administration | DV workflow with CCA → BT → PB approval chain, check register, cash-advance ledger with due dates and blocking of new advances while one is unliquidated, petty cash module, construction-in-progress tracking |
| VI Inventories (p.37–43) | BT is property officer; PR → PO → AIR → Stock Card → RIS → monthly SSMI; ICS for items lasting > 1 year; annual physical count (RISM); write-down to NRV; expired stock expensed | Inventory module with moving-average costing, document chain, month-end expense posting, year-end count and reconciliation |
| VII Investment Property, PPE, Biological Assets (p.44–59) | PPE at cost, depreciated; infrastructure counts as PPE; PAR renewed every 3 years; PEC (BT) and PELC (accountant); impairment; biological assets at fair value less cost to sell, revalued each reporting date | Fixed-asset register with depreciation schedule, custodian tracking, disposal, impairment entries; biological asset card and quarterly report |
| VIII Miscellaneous Transactions (p.60–67) | Loans, donations, lost property, overpayments, bonds, refunds and similar | Journal-voucher templates for each case |
| IX Adjusting and Closing Entries (p.68–69) | Year-end adjustments; closing income and expense to Accumulated Surplus/(Deficit) | Automated period-end routine |
| X Books, Trial Balances, Statements (p.70–72) | Books kept by C/M Accountant; trial balances; who signs the statements; which reports go where and when | Report generator and submission calendar |
| XI Special Trust Funds (p.73–77) | Registry of STF per fund; unspent LDRRMF becomes STF; conditional grants are liabilities until spent | STF registry with per-fund balances and release-to-income logic |
| XII Other Provisions (p.78–84) | Fiscal responsibilities of PB, BT, CCA, SB; bonding of accountable officers; record custody; transfer of accountability; rendition of accounts | Roles and permissions, bond register, turnover checklist, audit trail |
| XIII–XIV Chart of Accounts and Descriptions (p.85–150+) | The full account list with codes and definitions | The seed data for the system's account master (section 3) |
| XV Appendices A–C | Flowcharts for collections and disbursements; Matrix of Reports and Forms (who prepares, how many copies, to whom, when) | Section 5's digitization table and the notification/submission calendar |
| XVI Annexes 1–43 | Every form layout | The screens and printouts of the app (section 5) |

## Chart of Accounts (Chapter XIII, pp. 85–97)

The chart is fixed by COA and must be loaded into the system exactly as coded. Codes follow the pattern **C-GG-SS-AAA** (class, group, sub-group, account); an accumulated depreciation account ends in **1** and an accumulated impairment account in **2** of the parent's number (e.g. Buildings 1-07-04-010, Acc. Dep. 1-07-04-011, Acc. Impairment 1-07-04-012), and "Other" accounts use **990**. Your account master needs these columns: code, title, class (1 Asset, 2 Liability, 3 Equity, 4 Revenue, 5 Expense), normal balance (Dr/Cr), parent code, contra flag, whether it needs a Subsidiary Ledger, which statement line it rolls into, and the Chapter XIV description. The table below lists every account in the manual (280 account codes; a ready-to-import CSV with class, group, normal balance, contra link, statement line and subsidiary-ledger key accompanies this proposal); contra accounts are grouped with their parent to keep it readable.

| Class / Group | Account title | Code |
| --- | --- | --- |
| **ASSETS – Cash** | Cash – In Local Treasury | 1-01-01-010 |
|  | Petty Cash | 1-01-01-020 |
|  | Cash in Bank – Local Currency, Current Account | 1-01-02-010 |
| **Investments** | Investment in Time Deposits | 1-02-01-010 |
| **Receivables** | Accounts Receivable (Allowance for Impairment –011) | 1-03-01-010 |
|  | Due from Local Government Units | 1-03-02-010 |
|  | Advances for Payroll | 1-03-03-010 |
|  | Advances to Officers and Employees | 1-03-03-020 |
|  | Receivables – Disallowances/Charges | 1-03-04-010 |
|  | Due from Officers and Employees | 1-03-04-020 |
|  | Due from NGO/POs | 1-03-04-030 |
|  | Other Receivables (Allowance –991) | 1-03-04-990 |
| **Inventories** | Merchandise Inventory | 1-04-01-010 |
|  | Welfare Goods for Distribution | 1-04-02-010 |
|  | Drugs and Medicines for Distribution | 1-04-02-020 |
|  | Other Supplies and Materials for Distribution | 1-04-02-990 |
|  | Office Supplies Inventory | 1-04-03-010 |
|  | Accountable Forms, Plates and Stickers Inventory | 1-04-03-020 |
|  | Construction Materials Inventory | 1-04-03-030 |
|  | Other Supplies and Materials Inventory | 1-04-03-990 |
| **Prepayments** | Advances to Contractors | 1-05-01-010 |
|  | Other Prepayments | 1-05-01-990 |
| **Investment Property** | Investment Property – Land (Acc. Impairment –012) | 1-06-01-010 |
|  | Investment Property – Buildings (Acc. Dep. –021, Acc. Impairment –022) | 1-06-01-020 |
| **PPE – Land** | Land (Acc. Impairment –012) | 1-07-01-010 |
| **PPE – Land Improvements** | Other Land Improvements (–991, –992) | 1-07-02-990 |
| **PPE – Infrastructure** | Road Networks (–011, –012) | 1-07-03-010 |
|  | Flood Control Systems (–021, –022) | 1-07-03-020 |
|  | Sewer Systems (–031, –032) | 1-07-03-030 |
|  | Water Supply Systems (–041, –042) | 1-07-03-040 |
|  | Parks, Plazas and Monuments (–051, –052) | 1-07-03-050 |
|  | Other Infrastructure Assets (–991, –992) | 1-07-03-990 |
| **PPE – Buildings and Other Structures** | Buildings (–011, –012) | 1-07-04-010 |
|  | School Buildings (–021, –022) | 1-07-04-020 |
|  | Hospitals and Health Centers (–031, –032) | 1-07-04-030 |
|  | Markets (–041, –042) | 1-07-04-040 |
|  | Other Structures (–991, –992) | 1-07-04-990 |
| **PPE – Machinery and Equipment** | Machinery (–011, –012) | 1-07-05-010 |
|  | Office Equipment (–021, –022) | 1-07-05-020 |
|  | Information and Communication Technology Equipment (–031, –032) | 1-07-05-030 |
|  | Communication Equipment (–041, –042) | 1-07-05-040 |
|  | Construction and Heavy Equipment (–051, –052) | 1-07-05-050 |
|  | Disaster Response and Rescue Equipment (–061, –062; SLs 01 Firefighting, 02 Flood, 03 Earthquake, 04 Volcanic, 05 Landslide) | 1-07-05-060 |
|  | Military, Police and Security Equipment (–071, –072) | 1-07-05-070 |
|  | Sports Equipment (–081, –082) | 1-07-05-080 |
|  | Technical and Scientific Equipment (–091, –092) | 1-07-05-090 |
|  | Other Machinery and Equipment (–991, –992) | 1-07-05-990 |
| **PPE – Transportation Equipment** | Motor Vehicles (–011, –012) | 1-07-06-010 |
|  | Watercrafts (–021, –022) | 1-07-06-020 |
|  | Other Transportation Equipment (–991, –992) | 1-07-06-990 |
| **PPE – Furniture, Fixtures and Books** | Furniture and Fixtures (–011, –012) | 1-07-07-010 |
|  | Books (–021, –022) | 1-07-07-020 |
| **PPE – Leased Assets** | Leased Assets, Land (–012) | 1-07-08-010 |
|  | Leased Assets, Buildings and Other Structures (–021, –022) | 1-07-08-020 |
|  | Leased Assets, Machinery and Equipment (–031, –032) | 1-07-08-030 |
|  | Leased Assets, Transportation Equipment (–041, –042) | 1-07-08-040 |
|  | Other Leased Assets (–991, –992) | 1-07-08-990 |
| **PPE – Leased Assets Improvements** | Leased Assets Improvements, Land (–011, –012) | 1-07-09-010 |
|  | Leased Assets Improvements, Buildings (–021, –022) | 1-07-09-020 |
|  | Other Leased Assets Improvements (–991, –992) | 1-07-09-990 |
| **PPE – Construction in Progress** | CIP – Land Improvements | 1-07-10-010 |
|  | CIP – Infrastructure Assets | 1-07-10-020 |
|  | CIP – Buildings and Other Structures | 1-07-10-030 |
|  | CIP – Leased Assets | 1-07-10-040 |
|  | CIP – Leased Assets Improvements | 1-07-10-050 |
| **PPE – Other** | Other Property, Plant and Equipment (–991, –992) | 1-07-99-990 |
| **Biological Assets** | Biological Assets | 1-08-01-010 |
| **LIABILITIES – Payables** | Accounts Payable | 2-01-01-010 |
|  | Due to Officers and Employees | 2-01-01-020 |
|  | Interest Payable | 2-01-01-030 |
|  | Operating Lease Payable | 2-01-01-040 |
|  | Finance Lease Payable | 2-01-01-050 |
|  | Leave Benefits Payable | 2-01-01-060 |
| **Provisions** | Other Provisions | 2-01-02-010 |
| **Loans** | Loans Payable – Domestic | 2-01-03-010 |
| **Inter-Agency Payables** | Due to BIR | 2-02-01-010 |
|  | Due to GSIS | 2-02-01-020 |
|  | Due to Pag-IBIG | 2-02-01-030 |
|  | Due to PhilHealth | 2-02-01-040 |
|  | Due to NGAs | 2-02-01-050 |
|  | Due to GOCCs | 2-02-01-060 |
|  | Due to LGUs | 2-02-01-070 |
| **Trust Liabilities** | Trust Liabilities | 2-03-01-010 |
|  | Guaranty/Security Deposits Payable | 2-03-01-020 |
|  | Trust Liabilities – DRRMF | 2-03-01-030 |
| **Other Payables** | Other Payables | 2-99-99-990 |
| **EQUITY** | Government Equity | 3-01-01-010 |
|  | Prior Years' Adjustments | 3-01-01-020 |
|  | Revenue and Expense Summary (closing account) | 3-01-02-010 |
| **REVENUE – Tax (non-exchange)** | Real Property Tax | 4-01-01-010 |
|  | Business Tax | 4-01-02-010 |
|  | Share on tax from sand, gravel and other quarry products | 4-01-02-020 |
|  | Fees and Charges on commercial breeding of fighting cocks, cockfights and cockpits | 4-01-03-010 |
|  | Fees and Charges on places of recreation which charge admission fees | 4-01-03-020 |
|  | Fees and Charges on billboards, signboards, neon signs and outdoor advertisements | 4-01-03-030 |
|  | Share from Internal Revenue Collections | 4-01-04-010 |
|  | Other Taxes | 4-01-04-990 |
|  | Tax Revenue – Fines and Penalties – Property / Goods and Services / Permit Fees / Others | 4-01-05-010 / 020 / 030 / 990 |
| **Subsidy/Assistance** | Subsidy from National Government | 4-02-01-010 |
|  | Subsidy from Other Local Government Units | 4-02-01-020 |
|  | Transfer of Unspent Previous Years' LDRRMF | 4-02-01-030 |
| **Shares, Grants, Donations** | Share from National Wealth | 4-03-01-010 |
|  | Grants and Donations in Cash | 4-03-02-010 |
|  | Grants and Donations in Kind | 4-03-02-020 |
| **REVENUE – Exchange** | Clearance and Certification Fees | 4-04-01-010 |
|  | Other Service Revenue | 4-04-01-990 |
|  | Garbage Fees | 4-04-02-010 |
|  | Market Fees | 4-04-02-020 |
|  | Other Business Income | 4-04-02-990 |
| **Gains** | Gain on Sale of Property, Plant and Equipment | 4-05-01-010 |
|  | Gain on Revaluation of Biological Assets | 4-05-01-020 |
| **EXPENSES – Personnel Services** | Salaries and Wages – Regular / Casual-Contractual | 5-01-01-010 / 020 |
|  | PERA, Clothing/Uniform, Subsistence, Productivity Incentive, Honoraria, Year End Bonus, Cash Gift, Other Bonuses | 5-01-02-010 … 070, 990 |
|  | Retirement and Life Insurance Premiums, Pag-IBIG, PhilHealth, Employees Compensation Insurance | 5-01-03-010 … 040 |
|  | Terminal Leave Benefits, Other Personnel Benefits | 5-01-04-010, 990 |
| **MOOE** | Travelling Expenses – Local / Foreign | 5-02-01-010 / 020 |
|  | Training Expenses | 5-02-02-010 |
|  | Office Supplies, Accountable Forms, Welfare Goods, Drugs and Medicines, Fuel-Oil-Lubricants, Other Supplies Expenses | 5-02-03-010 … 050, 990 |
|  | Water, Electricity | 5-02-04-010, 020 |
|  | Postage and Courier, Telephone, Internet Subscription, Cable/Satellite/Telegraph/Radio | 5-02-05-010 … 040 |
|  | Demolition and Relocation; Desilting and Dredging | 5-02-06-010, 020 |
|  | Auditing, Consultancy, Other Professional Services | 5-02-07-010, 020, 990 |
|  | Environment/Sanitary, Janitorial, Security, Other General Services | 5-02-08-010 … 030, 990 |
|  | Repairs and Maintenance – Land Improvements / Infrastructure / Buildings / Machinery / Transportation / Furniture / Leased Assets / Leased Improvements / Other PPE | 5-02-09-010 … 080, 990 |
|  | LGU Equity on Other LGU/National/Foreign Funded Projects; Transfer to TF unutilized LDRRMF; Transfer of SK allocation; Subsidies – Others | 5-02-10-010 … 030, 990 |
|  | Fidelity Bond Premiums; Insurance Expenses | 5-02-11-010, 020 |
|  | Extraordinary and Miscellaneous Expenses | 5-02-12-010 |
|  | Advertising, Representation, Transportation and Delivery, Rent/Lease, Membership Dues, Subscription, Donations, Other MOOE | 5-02-99-010 … 070, 990 |
| **Financial Expenses** | Interest Expenses, Bank Charges, Other Financial Charges | 5-03-01-010, 020, 990 |
| **Non-Cash Expenses** | Depreciation – Land Improvements / Infrastructure / Buildings / Machinery / Transportation / Furniture-Fixtures-Books / Leased Assets / Leased Improvements / Other PPE | 5-04-01-010 … 080, 990 |
|  | Impairment Loss – same nine classes | 5-04-02-010 … 080, 990 |
|  | Loss on Sale of PPE; Loss on Sale of Assets; Loss of Assets; Loss on Revaluation of Biological Assets | 5-04-03-010 … 040 |

Three things to build into the account master beyond the list: (1) subsidiary-ledger requirements – every receivable, payable, advance, trust liability, PPE and inventory account needs an SL per debtor/creditor/officer/fund/item (Annex 4); (2) fund tagging – every posting carries a fund code (General Fund, SK, LDRRMF, 20% DF, each STF) so the RAO, RSTF and Statement of Comparison can be produced per fund without separate charts; (3) the Chapter XIV descriptions (pp. 98–150) as the help text shown next to each account when a user picks it, so a non-accountant treasurer chooses correctly.

## Books of accounts: journals and ledgers (Annexes 1–5, Chapter X)

The system keeps four books per barangay, all owned by the C/M Accountant, plus the Journal Voucher that feeds the General Journal. In a database these are not four separate tables: they are **one journal-entry table** (header + lines) with a `book` flag, and the GL and SL are **views** of it. That is what makes the system correct by construction – a posting cannot land in the journal but miss the ledger.

| Book | Annex | Records | Columns the printout must show | Rule in the manual |
| --- | --- | --- | --- | --- |
| Journal of Cash Transactions (JCT) | 1 | All cash transactions: collections, deposits, checks issued, cash advances, petty cash | Date, Particulars, Reference (RCD/DV/JEV no.), Cash–In Local Treasury Dr/Cr, Cash in Bank–LCCA Dr/Cr, Income columns, Expense columns, Sundry (title, code, Dr, Cr); monthly totals; recap of sundry columns; one sheet series per year | Sources are the RCD, RBDCM, DVs, LRs. Certified correct on every page by the C/M Accountant |
| General Journal (GJ) | 2 | All non-cash transactions (receipt of deliveries on account, depreciation, adjustments, closing) | Date, JEV No., Particulars, Account Code, posting-reference tick, Dr, Cr; new sheet each month; totals carried forward | Entries only from an approved Journal Voucher; Dr total must equal Cr total |
| General Ledger (GL) | 3 | One sheet per account in Chart-of-Accounts order | Account title/code, Date, Particulars, Reference (JEV no.), Dr, Cr, running Balance (negative in parentheses) | Postings come only from JCT and GJ; footed monthly; ruled and closed at year-end with balance carried forward |
| Subsidiary Ledger (SL) | 4 | Detail under each controlling account (per debtor, creditor, officer, fund, property item) | Sheet No., Account title/code, Description, Creditor/Debtor, Address, Contact, Date, Particulars, Reference, Dr, Cr, Balance | SL total must reconcile to the GL control account every month |
| Journal Voucher (JV) | 5 | The source document for every GJ entry, including adjusting and closing entries | JV No. (YY-MM-serial, one series per year), Date, Accounts and Explanation, Account Code, Ref., Dr, Cr, Total, Prepared by (Barangay Bookkeeper), Approved by (C/M Accountant); 2 copies (COA, Accounting file) | Prepared by the Accounting Unit for all non-cash transactions |

How the system should implement them:

1. **Journal entry table**: `entry_id, barangay_id, fund, book (JCT/GJ), date, period (YYYY-MM), reference_type (RCD/RBDCM/DV/Payroll/LR/JV), reference_no, particulars, status (draft/approved/posted), prepared_by, approved_by`. Lines: `account_code, sl_key (debtor/creditor/officer/fund/item), debit, credit`. A posting is accepted only if debits equal credits and every account exists in the chart.
2. **Automatic entries**: the BT's reports generate draft entries using the pro-forma entries in Chapters IV–XI (collections 4.3.1–4.3.3, disbursements 5.3.1, cash advances, petty cash, inventories 6.3, PPE 7.4, STF 11.3, miscellaneous 8.1). The Barangay Bookkeeper reviews, the C/M Accountant approves (Box E on the DV, Payroll, RCD and LR is exactly this step).
3. **GL view**: sum of lines by account and period, with running balance, printed in chart order on the Annex 3 layout.
4. **SL view**: same, grouped by account + sl\_key, with a monthly reconciliation check that the SL total equals the GL balance; a mismatch is flagged, not silently allowed.
5. **Trial balances**: pre-closing (after adjusting JVs) and post-closing (after closing JVs), both generated from the GL view (Section 10.2).
6. **Period lock**: once a month's JCT is certified, the period is closed and only a JV dated in an open period can change it, keeping the printed books and the database identical.
7. **Numbering**: every JV, RCD, DV, PCV, Payroll, LR, PR, PO, PAR, ICS, RIS, RAAF, RBDCM, IIAR, ARDPESM and SSMI uses the manual's `YYYY-MM-serial` pattern with one series per year (SSMI: one series per month). The system must issue these numbers itself and never allow gaps or duplicates.

## All 43 annex forms to digitize

Every form below becomes a screen (data entry), a record (stored, numbered, signed off) and a printout (the annex layout, since COA auditors still receive paper copies). "Who" and "when" come from the annex instructions and the Appendix C matrix. BT = Barangay Treasurer, CCA = Chairman, Committee on Appropriations, PB = Punong Barangay, Acct = C/M Accountant, DBC = Deputized Barangay Collector.

| Annex | Form | Prepared by | Frequency / trigger | Copies and who gets them | What the system does with it |
| --- | --- | --- | --- | --- | --- |
| 1 | Journal of Cash Transactions | Acct | Monthly | Accounting | Generated from posted cash entries |
| 2 | General Journal | Acct | Monthly | Accounting | Generated from posted JVs |
| 3 | General Ledger | Acct | Monthly / year-end | Accounting | View per account |
| 4 | Subsidiary Ledger | Acct | Monthly | Accounting | View per account + detail key |
| 5 | Journal Voucher | Barangay Bookkeeper, approved by Acct | As needed | COA, Accounting | Entry screen for non-cash entries; approval posts to GJ |
| 6 | Record of Appropriations and Obligations (RAO) | CCA | Continuous; one per fund source (regular, SK 10%, LDRRMF 5%, 20% DF, continuing) | CCA | Budget ledger: appropriations in, obligations out, by PS/MOOE/FE/CO; available balance drives the CCA certification |
| 7 | Statement of Appropriations, Obligations and Balances (SAOB) | CCA, noted by PB | Monthly; year-end copy to Acct | PB, SB, CCA | Report from the RAO: original, supplemental, final, obligations, balance |
| 8 | Cashbook | BT | Daily; certified monthly | BT; certified copy to Acct with the TL | Four-section running ledger: Cash in Local Treasury, Cash in Bank, Cash Advance, Petty Cash (see Annex 8 example) |
| 8.1 | Cashbook – Disbursing Officer | Disbursing officer other than BT | Daily per cash advance | DO | Separate cashbook per cash advance type |
| 9 | Report of Collections and Deposits (RCD) | BT | Daily transactions, submitted monthly by the 5th | COA via Acct (with duplicate ORs), Acct, C/M Treasurer | Generated from ORs and deposit slips; includes accountable-forms section and Box for accounting entries |
| 9.1 | Report of Collections and Remittances (RCR) | DBC | Daily, turned over to BT | COA via Acct, C/M Treasurer, BT | Collector's daily report; BT acknowledges; feeds the RCD |
| 10 | Report of Bank Debit/Credit Memos (RBDCM) | Acct | Monthly from the bank statement | Acct (JCT basis, COA), BT, Acct file | Bank memo capture (IRA credits, bank charges, dishonored checks); posts to JCT and updates BT cashbook |
| 11 | Bank Reconciliation Statement | Barangay Bookkeeper, certified by Acct | Monthly, to COA by the 20th | COA, Acct, PB/BT | Book vs bank with reconciling items and comments |
| 12 | Disbursement Voucher (DV) | BT prepares; Boxes A (CCA), B (BT), C (PB), D (payee), E (Bookkeeper/Acct) | Per claim | COA via Acct, BT, Payee | Core workflow document with four e-certifications and check details |
| 13 | Petty Cash Voucher | Requestor; PB approves; BT pays; liquidation boxes C/D | Per petty expense ≤ ₱1,000 | COA via Acct, BT | Two-stage form: grant then liquidation |
| 13.1 | Petty Cash Record | Petty Cash Custodian | Daily | PCC | Running Dr/Cr/Balance per PCV |
| 14 | Payroll | BT; Boxes A–E | Per pay period | COA via Acct, Acct, BT | Lines per employee: salaries, honoraria, other benefits, deductions, net; recipient signature |
| 15 | Liquidation Report | Accountable officer; received by Accounting | Payroll: 5 days; local travel: 30 days; foreign: 60 days; special purpose: on completion | COA via Acct, Acct, AO | Closes a cash advance; computes refund or reimbursement; Box for accounting entries |
| 16 | Transmittal Letter | BT, noted by PB | Monthly, within 10 days after month-end | Acct, Auditor, BT | Auto-generated cover list of paid DVs/Payrolls, RCDs, other reports; receiving signature |
| 17 | Summary of Petty Cash Disbursements | BT / Petty Cash Custodian | On replenishment (≥ 75% used) and year-end liquidation | COA via Acct (attached to DV), BT | Lists PCVs; attaches to replenishment DV |
| 18 | Report of Accountability for Accountable Forms (RAAF) | BT and each DBC | Monthly | COA, Acct, BT | Beginning, received, issued, ending quantities and serial ranges for ORs, cash tickets, checks; spoiled/stale checks reported here |
| 19 | Acknowledgement Receipt for Donated Property, Equipment, Supplies and Materials | BT; PB acknowledges; donor conforms | On receipt of donation | Donor, Acct, BT | Records donated items at declared or fair value; posts Grants and Donations in Kind |
| 20 | Requisition and Issue Slip (RIS) | Requesting person; PB approves; BT issues | As needed | BT, requester, Acct | Draws down stock; feeds Stock Card, ICS/PAR and SSMI |
| 21 | Inventory Custodian Slip (ICS) | BT | On issue of items with life > 1 year | BT, recipient | Custodian record for small tangible items; cancelled on return |
| 22 | Stock Card | BT | Per item, every receipt and issue | BT | Quantity ledger per supply item |
| 23 | Purchase Request | Requesting person; PB approves | As needed | PO attachment, requester, BT | Start of procurement chain; links to APP |
| 24 | Purchase Order | BT; supplier conforms; CCA certifies appropriation | As needed | Supplier, BT, COA | Creates an obligation in the RAO; stores mode of procurement, delivery and payment terms |
| 25 | Property Acknowledgement Receipt (PAR) | BT; end-user receives | On issue of PPE; renew every 3 years or on change of custodian | BT, end-user, Acct | Custodian record per property number |
| 26 | Property/Equipment Card (PEC) | BT | Per item | BT | Physical register: location, cost, repairs, transfers |
| 26.1 | Property/Equipment Ledger Card (PELC) | Acct | Per item class | Acct | Accounting register: account code, useful life, monthly depreciation rate, accumulated depreciation, book value |
| 27 | Acceptance and Inspection Report (AIR) | BT (property officer) and Inspection Officer | On every delivery | Acct (with PO/PR copies), DV attachment, BT | Confirms receipt (complete/partial); creates inventory or PPE record and the payable entry |
| 28 | Return and Receipt of Property/Equipment (RRPE) | BT | On return of unserviceable property | Accountable person, BT, Acct | Cancels the PAR; marks item for disposal |
| 29 | Inventory, Inspection and Appraisal Report (IIAR) | BT (items), Acct (cost, depreciation, NBV), Inspector (appraised value, mode), witness, PB approves | On disposal | Acct (JV basis), BT, Acct file | Disposal workflow; generates derecognition JV |
| 30 | Report on Inventory of Property and Equipment (RIPE) | Inventory Committee; PB approves | Yearly, by 10 January | COA, Acct, BT | Physical count vs PEC/PAR/ICS with shortage/overage; includes unrecorded items |
| 31 | Report on Inventory of Supplies and Materials (RISM) | Inventory Committee; PB approves | Yearly, by 10 January | COA, Acct, BT | Physical count vs stock cards |
| 32 | Summary of Supplies and Materials Issued (SSMI) | BT (weekly per instructions; monthly per Ch. VI); Acct costs it | Weekly/monthly | Acct, COA, file | Quantity per RIS; Accounting applies moving-average unit cost and totals for the expense JV |
| 33 | Registry of Special Trust Fund (RSTF) | CCA | Per STF until fully used | CCA | Sources (date, particulars, ref, amount, year) and charges; basis of CCA certification on STF-funded DVs |
| 34 | Statement of Management Responsibility | PB, BT, Acct sign | Year-end | With the FS | Fixed text with signatures |
| 35 | Statement of Financial Performance | Acct | Monthly (as Statement of Receipts and Expenditures, within 30 days) and year-end | COA, Sangguniang Panlungsod/Bayan, SB, Acct | Revenue by group, expenses by PS/MOOE/Non-cash/Financial, transfers, surplus; note references |
| 36 | Statement of Financial Position (condensed) | Acct | Year-end, within 60 days | same 4 copies | Current/non-current assets and liabilities, Government Equity |
| 37 | Statement of Changes in Net Assets/Equity | Acct | Year-end | same | Opening balance, policy changes, prior-year adjustments, surplus, closing |
| 38 | Statement of Cash Flows | Acct | Year-end | same | Direct method: operating, investing, financing inflows/outflows; ties to Note 15 and Note 28 |
| 39 | Statement of Comparison of Budget and Actual Amounts | Acct, from REAI (BT) and SAOB (CCA) | Year-end | same | Original budget, final budget, difference, actual, difference; revenue lines per income account; expenses by PS/MOOE/CO and by fund (20% DF, SK, LDRRMF, continuing) |
| 40 | Notes to Financial Statements | Acct | Year-end | same | 30 notes with fixed structure: policies, then one note per statement line (Notes 3–27), cash-flow reconciliation (28), budget reconciliation (29) |
| 41 | Record of Estimated and Actual Income (REAI) | BT | Monthly; to Acct at year-end | Acct, BT | Income estimates (A) from the budget vs actual collections (B) per income account, cumulative |
| 42 | Biological Assets Property Card | Caretaker | Per asset type, every change | Caretaker | Quantity and fair value: additions (purchase, birth), reductions (sale, death), balance |
| 43 | Quarterly Report of Biological Assets | Caretaker | Quarterly | Accounting (to COA), caretaker, Accounting file | Movement report feeding the revaluation JV |

Not numbered as annexes but required by the text and also needed as records: Official Receipt (Accountable Form 51) and other receipts, Deposit Slip, Punong Barangay Certification for checks (COA Circular 2012-005), Notice of Loss and Request for Relief from Accountability (within 30 days), Turnover–Receipt form for outgoing officials, fidelity bond records, Appropriation Ordinance and Annual Procurement Program.

## Financial reports the system must generate

All reports come from the same posted entries, so the report layer is mostly mapping accounts to statement lines. The table lists each output, its deadline from Chapter XII and Appendix C, and the data it is built from.

| Report | Deadline | Built from | Notes for the builder |
| --- | --- | --- | --- |
| RCD, RCR, Cashbook certification, RAAF, LRs, paid DVs/Payrolls with Transmittal Letter | Within 10 days after month-end (RCD by the 5th) | BT's daily records | The TL is the monthly "package" the barangay sends; make it one button |
| Monthly Statement of Receipts and Expenditures (Statement of Financial Performance, monthly form) | 30 days after month-end, copy to Auditor | GL | Same layout as Annex 35 |
| Collections and disbursements accounts and reports of each barangay to COA | 15th working day of the following month | JCT, RCD, DVs | Accountant-side submission |
| Bank Reconciliation Statement | 20th of the following month | GL Cash in Bank, bank statement, RBDCM, outstanding checks | Needs a check register with issued/cleared status |
| SAOB | Monthly; year-end to Acct | RAO | Per fund and consolidated |
| RSTF balances | Monthly | RSTF | Per trust fund |
| Quarterly Report of Biological Assets | Quarterly | BAPC | Only for barangays with livestock, trees, aquaculture |
| Pre-closing and post-closing Trial Balances | Year-end | GL | After adjusting and after closing JVs |
| Statement of Financial Performance (Annex 35) | Within 60 days after year-end, 4 copies (COA, Sangguniang Panlungsod/Bayan, SB, Acct) | GL revenue and expense accounts, two years side by side | Lines: Tax Revenue, IRA share, National Wealth, Service and Business, Grants and Donations, Gains; PS, MOOE, Non-cash, Financial; Transfers From/To |
| Statement of Financial Position (Annex 36) | Same | GL asset, liability, equity accounts | Current vs non-current split: receivables and investments appear in both depending on term |
| Statement of Changes in Net Assets/Equity (Annex 37) | Same | Government Equity, Prior Years' Adjustments, surplus |  |
| Statement of Cash Flows (Annex 38) | Same | JCT (cash entries classified operating / investing / financing) | Direct method; tag every cash line with a cash-flow category at posting time rather than deriving it later |
| Statement of Comparison of Budget and Actual Amounts (Annex 39) | Same | REAI (income estimates vs actual) and SAOB (appropriations vs obligations) | Columns: original budget, final budget, difference, actual, difference; rows per income account and per expense class, with 20% DF, SK, LDRRMF and continuing appropriations shown separately |
| Notes to Financial Statements (Annex 40) | Same | All of the above | 30 notes; Notes 3–27 are breakdown tables of statement lines, Note 9b lists honoraria of PB, Kagawads, SK rep, BT, Secretary; Note 21 PPE schedule; Note 28 cash-flow reconciliation; Note 29 budget reconciliation |
| Statement of Management Responsibility (Annex 34) | With the year-end FS | Fixed text | Signed PB, BT, Acct |
| Reports on Property Inventory and Supplies Inventory (RIPE, RISM) | By 10 January | Physical count vs cards | PB submits to Acct and COA |
| Year-end consolidated FS of all barangays in the city/municipality | Year-end | All barangays' GLs | Accountant-side feature; digital copies of TBs, FSs and schedules go to COA |

Two cross-checks the system should run before any statement is released: the Cash in Bank balance in the GL must equal the BT's Cashbook balance after the bank reconciliation (Section 12.1.3.d), and every SL total must equal its GL control account.

## End-to-end transaction flows

> **Diagram (described):** Two lanes. *Barangay lane* — Spending row: Appropriation Ordinance (SB) → RAO, Annex 6 (CCA certifies) → DV / Payroll / PO (Annexes 12, 14, 24) → Check + PB Certification → Cashbook (Annex 8, daily). Collecting row: Official Receipt (Accountable Form 51) → RCD / RCR (Annexes 9, 9.1) → Deposit to AGDB (intact, daily) → Cashbook. *City/Municipal Accountant lane* — Transmittal Letter (monthly, by the 10th) → JCT (cash) and GJ via JV (Annexes 1, 2, 5) → GL and SL (Annexes 3, 4) → Trial balances, adjusting and closing → Financial Statements (Annexes 34–40). The Cashbook feeds the Transmittal Letter.

Every peso enters through a numbered document on the barangay side and reaches the statements only through the Accountant's journals; the bank statement enters separately as the RBDCM (Annex 10), which the Accountant posts to the JCT and sends back to the BT to update the Cashbook. The flows below are the ones the app must enforce, each with the control points from the manual.

**1. Budget and obligation (Chapter III, Appendix B).** Appropriation ordinance → RAO per fund source → every PO, DV and Payroll goes first to the CCA, who checks the RAO (or the RSTF for trust-funded items) and certifies Box A → the obligation is posted to the RAO at the gross amount. Hard rule: an obligation that exceeds the available balance is refused (3.1.1). Monthly SAOB to PB and SB.

**2. Collections (Chapter IV, Appendix A).** OR issued in strict sequence (cancelled ORs still listed) → DBC collections reported on an RCR and turned over daily → BT prepares the RCD and deposits intact daily (weekly or at ₱5,000 if the bank is far) → Cashbook updated → RCD with duplicate ORs and validated deposit slips to the Accountant by the 5th → JCT entry: Dr Cash–In Local Treasury / Cr income (or liability for trust receipts, or asset for refunds), then Dr Cash in Bank / Cr Cash–In Local Treasury on deposit. Collections made as deputized collector of the city/municipality are remitted to the C/M Treasurer, not deposited. Trust receipts must carry their purpose on the OR and are copied to the CCA for the RSTF.

**3. Disbursement by check (Section 5.2.1, Appendix B).** DV with supporting documents → CCA Box A → BT Box B (funds available, documents complete) → PB Box C (approve) → BT prepares and signs check → PB countersigns and issues the Punong Barangay Certification to the bank → BT records in Cashbook under Cash in Bank–Check Issued → payee signs Box D on release → at month-end the TL carries paid DVs, checks and PBC copies to the Accountant → JCT entry: Dr expense/asset, Cr Due to BIR (withholding), Cr Cash in Bank. The app needs a check register (number, date, payee, amount, PBC number, status issued/cleared/stale/spoiled/lost) because the bank reconciliation and the RAAF both read it.

**4. Cash advances (Sections 5.2.2–5.2.4).** Payroll advance = net payroll, liquidated within 5 days; travel advance liquidated within 30 days (local) or 60 (foreign); special-purpose advance liquidated on completion. Grant: Dr Advances for Payroll / Advances to Officers and Employees, Cr Cash in Bank. Liquidation Report: Dr expense (Salaries, Honoraria, Travelling, Training), Cr the advance (and Cr Due to BIR for payroll). Rules to enforce: no new advance while one is unliquidated; no transfer between officers; unused advance returned within two months with an OR; all advances liquidated at year-end.

**5. Petty cash (Section 5.2.5).** Set-up DV in the custodian's name (Dr Petty Cash / Cr Cash in Bank), amount ≤ one month's recurring expenses and ≤ 20% of available funds. Each PCV ≤ ₱1,000 for direct purchases, recorded in the Petty Cash Record. Replenish at 75% via DV + SPCD (Dr expenses / Cr Cash in Bank). Full liquidation at year-end or change of custodian: Dr Cash–In Local Treasury + expenses / Cr Petty Cash; the next custodian starts a new account.

**6. Procurement, inventory and property (Chapters VI–VII).** PR (PB approves) → PO (CCA certifies appropriation, supplier conforms) → delivery → AIR (property officer + inspector) → Stock Card or PEC updated → Accountant posts Dr Inventory or PPE / Cr Accounts Payable, Cr Due to BIR → DV pays the payable. Issuance: RIS → Stock Card → ICS for items lasting > 1 year, PAR for PPE → monthly SSMI costed at moving average → JV Dr expense / Cr Inventory. Depreciation: straight-line, 5% residual, starting the month the asset is available for use, posted monthly or at least at year-end from the PELC. Disposal: RRPE → IIAR (BT items, Accountant cost/NBV, inspector appraisal, witness, PB approval) → JV derecognizing cost and accumulated depreciation with gain or loss. Loss: Notice of Loss within 30 days → Dr Due from Officers and Employees + Accumulated Depreciation / Cr asset → COA decision either Dr Loss of Assets / Cr Due from O&E (relief granted) or payment by the officer (denied). Annual physical count: RIPE and RISM by 10 January, unrecorded items valued by the Appraisal Committee and taken up.

**7. Special trust funds (Chapter XI).** Receipt: Dr Cash / Cr Trust Liabilities (or Trust Liabilities–DRRMF) and a line in the RSTF. Spending: CCA certifies against the RSTF balance; Dr expense or asset / Cr Cash or Accounts Payable; then Dr Trust Liability / Cr Grants and Donations or Subsidy from National Government for the spent portion. Year-end: unspent LDRRMF current-year appropriation moves to the STF (Dr Transfer to TF unutilized LDRRMF / Cr Trust Liabilities–DRRMF); unspent SK allocation likewise.

**8. Miscellaneous (Chapter VIII).** Cash shortage (Dr Due from O&E / Cr Cash–In Local Treasury on the auditor's certification), cash overage (Dr Cash / Cr Miscellaneous Income with an OR), dishonored check (Dr income / Cr Cash in Bank on the bank debit memo; OR cancelled; re-collection), lost/spoiled/stale checks (restore the payable, reissue a replacement check with a new PBC; report in the RAAF; stale after 6 months with a notice one month before), disallowances taken up only when final and executory (Dr Receivables–Disallowances/Charges / Cr expense).

**9. Bank reconciliation (4.2.6–4.2.8, Annex 11).** Bank statement → RBDCM (credit memos such as IRA, national wealth share, RPT share; debit memos such as bank charges and dishonored checks) → JCT and BT Cashbook → BRS by the 20th comparing book and bank with outstanding checks and deposits in transit.

**10. Period-end (Chapters IX–X).** Adjusting JVs (accruals, prepayments, depreciation, unearned revenue) → pre-closing trial balance → closing JVs (revenues and expenses to Revenue and Expense Summary, then to Government Equity) → post-closing trial balance → six statements and notes within 60 days, four copies, plus the consolidated FS of all barangays.

**11. People changes (Chapter XII).** Bonding of the BT (up to ₱10,000 bond amount) and every accountable officer; Turnover–Receipt when a PB or BT leaves, with the outgoing BT's Cashbook ruled, certified and submitted to the Accountant before clearance; semi-annual rendering of property accounts to the PB.

## Proposed architecture, data model and tool stack

Build one multi-tenant web application (a "tenant" is a city or municipality; its barangays sit under it) with a single PostgreSQL database, role-based access, and a PDF renderer that prints every annex in the manual's layout. The accounting engine is the smallest part of the build; the forms, workflows and reports are the bulk.

> **Diagram (described):** Four layers, top to bottom. *Users* (each sees only their barangay or LGU): Treasurer (phone or PC), CCA (certifies RAO), Punong Barangay (approves), Collectors and custodians, C/M Accountant (books, FS), COA auditor (read-only). *Application modules* (one login, one web app that also works offline): Budget (RAO, SAOB) · Collections (OR, RCD, RAAF) · Payments (DV, cash advances, petty cash) · Property (stock, PPE) · Trust funds (RSTF) · Ledger + reports. *Platform*: Roles per barangay/LGU · PostgreSQL (Supabase) · Numbering + audit trail · Annex PDFs (print layouts) · Offline sync. *Outputs and connectors*: Printed annexes (signed) · Excel/Google Drive export and backup · COA digital copies (TB, FS) · QuickBooks/Xero mirror (optional) · LGUSS-BIMS data exchange.

The accountant layer is the reason to build this as one system rather than 42,000 separate apps: the C/M Accountant already keeps every barangay's books, so a city with 30 barangays gets one login and 30 sets of books, and consolidation (Section 12.1.4.d) is a query, not a year-end project.

**Core data model (tables).** Master data: `lgu`, `barangay`, `official` (role, bond, term), `fund` (GF, SK, LDRRMF, 20% DF, continuing, each STF), `account` (the Chart of Accounts), `bank_account`, `supplier`, `employee`, `accountable_form` (OR booklets, cash tickets, check booklets with serial ranges). Budget: `appropriation` (ordinance, fund, PS/MOOE/FE/CO, amount, original/supplemental), `obligation` (linked PO/DV/Payroll, amount, CCA certification), `income_estimate`. Cash: `official_receipt`, `rcr`, `rcd`, `deposit`, `bank_memo`, `disbursement_voucher` (with the five boxes as status fields), `check`, `payroll` + `payroll_line`, `cash_advance`, `liquidation_report`, `petty_cash_fund`, `petty_cash_voucher`, `transmittal`. Property: `purchase_request`, `purchase_order`, `air`, `stock_item`, `stock_movement` (RIS/ICS), `property_item` (PEC/PELC fields, useful life, residual, custodian, PAR history), `depreciation_run`, `disposal` (RRPE/IIAR), `physical_count`, `biological_asset` + movements. Accounting: `journal_entry`, `journal_line`, `period` (open/closed), `trust_fund_registry`. Everything carries `barangay_id`, `fund_id`, `created_by`, timestamps, and an immutable `audit_log` of every change, because COA will ask who altered a record and when.

**Recommended stack for a non-developer owner.** You already deploy on Vercel and Netlify and keep files in Google Drive, so the practical path is: (1) **Supabase** for the database, login and row-level security (each user sees only their barangay or LGU); (2) a **Next.js web app** generated and maintained with Claude Code from a written spec (this document plus the annex layouts), hosted on Vercel; (3) **PDF generation** server-side (e.g. React-PDF or Puppeteer) for the annexes, since a printed, signed copy is still what COA receives; (4) a **PWA** (installable web app) for treasurers so it runs on a phone, with an Android wrapper on the Play Store later, the same route you planned for the booking app; (5) **Google Drive** export of monthly packages and Excel copies of ledgers. Pure no-code builders (Glide, Softr, Airtable) can prototype the forms, but double-entry posting, period locks, sequential numbering and multi-barangay security need a real database with server-side rules; keep the no-code tools for the pilot only.

**Non-negotiable system rules** (each maps to a manual provision): postings balance (1.2.2); accounts only from the chart (1.2.3); cash entries to JCT, non-cash to GJ via approved JV (1.2.5); obligation ≤ available appropriation (3.1.1); OR numbers sequential with no gaps and cancelled ORs retained (4.1.3); one depository account per barangay (4.1.15); DV cannot be paid without Boxes A, B, C (5.1.3); no new cash advance while one is open (5.1.7); petty cash caps and 75% replenishment trigger (5.2.5); moving-average inventory costing (6.1.6); straight-line depreciation, 5% residual, from month available for use (7.1.21–22); STF disbursement ≤ STF balance (11.1.2); closed periods are immutable; monthly SL-to-GL and Cashbook-to-GL reconciliation flags.

## Accounting connectors: what fits, what does not, recommendation

Recommendation: **do not make a commercial accounting package the system of record.** Build the ledger yourself (sections 3–4 define it completely) and use connectors at the edges. The accounting connectors available to you today are listed below; none is connected yet, while Google Drive, Vercel and Netlify are already connected.

| Connector | What it offers | Fit for this system |
| --- | --- | --- |
| Intuit QuickBooks (official) | Read-only reports: P&L, cash flow, benchmarking, transaction import | Reports use commercial formats (P&L, balance sheet), not the Annex 35–40 layouts; cannot hold the COA account codes as-is; no obligation/appropriation accounting; one QuickBooks company per barangay would mean 42,000 subscriptions |
| Meridian Connector for QuickBooks | Write access: bills, payments, deposits, expenses, customers, batch operations | Could mirror posted JCT/GJ entries into QuickBooks for a city that already uses it, but QuickBooks has no fund, RAO, RSTF, PAR/ICS or RAAF concepts |
| Xero (official) | Financial position, cash position, P&L, aged receivables/payables | Same limits; Xero's chart can be customised to the COA codes, but reports still would not match the annexes |
| Meridian Connector for Xero | Create accounts, bank transactions, invoices, contacts | Possible secondary ledger; same gaps |
| NumbersGame MCP | Query and update QuickBooks and Xero, reconciliations | Useful only if a mirror ledger exists |
| FreshBooks | Reports incl. general ledger and trial balance | Small-business invoicing focus; not suitable |
| Dext, Breezing, QuickStart | Bookkeeping-firm portfolio tools, crypto accounting, AI accounting | Not relevant |

Why a commercial ledger cannot be the core: (1) the Chart of Accounts, fund segregation (GF, SK, LDRRMF, 20% DF, STF) and obligation accounting are COA-prescribed and the Accountant certifies the annex-format books, not a QuickBooks report; (2) the RAO/RSTF appropriation control and the five-box DV workflow have no equivalent; (3) property, inventory custodian and accountable-forms registers are outside accounting software; (4) cost and connectivity: many barangays have intermittent internet and no budget for per-entity SaaS fees.

Where connectors do add value:

- **Google Drive (connected)**: archive each barangay's monthly transmittal package and year-end FS as PDFs and Excel; share folders with the COA audit team leader; keep an off-site backup.
- **Vercel / Netlify (connected)**: hosting and deployment of the web app and the PDF service.
- **QuickBooks or Xero via Meridian (optional, later)**: a one-way mirror of posted journal entries for cities whose accounting office already runs one of these for management reporting. Map COA codes to a custom chart; never post back into your ledger.
- **Bank feeds**: the AGDB is usually Landbank or DBP; neither exposes a public API for barangay accounts, so the RBDCM will be keyed in or imported from the bank's CSV statement. Design the bank-memo import to accept a spreadsheet.
- **LGUSS-BIMS (DILG)**: the DILG is rolling out the Barangay Information Management System to all barangays and reports it covers financial transactions among 11 sub-systems ([DILG Calabarzon, Dec 2025](https://calabarzon.dilg.gov.ph/dilg-pushes-full-digital-shift-in-barangays-through-nationwide-lguss-bims-adoption/)). Treat it as a system to exchange data with (barangay profile, officials, property list) and to position against: your product's differentiator is the C/M Accountant's books and the COA-format annexes end to end. Confirm what its finance sub-system actually covers before building overlapping features (see section 11).

## Step-by-step build plan and what you need to do

Start with one pilot city or municipality and two or three of its barangays, run the system in parallel with the paper books for a full year-end, and only then scale. The order below follows the manual's own flow: cash first (that is where the daily pain and the 10-day deadlines are), then the books, then property, then statements.

> **Diagram (described):** Six phases left to right, each closed by a gate. Foundation (Month 1: spec, chart seed, pilot LGU, DB) → gate: pilot city and barangay signed. Cash module (Months 2–3: OR, RCD, Cashbook, DV, checks, TL) → gate: one month run in parallel with paper. Budget + books (Months 3–5: RAO, SAOB, RSTF, JCT, GJ, GL, SL) → gate: Accountant certifies a month from the system. Property, pay (Months 5–7: PR-PO-AIR, PPE, payroll, petty cash) → gate: count and payroll reproduced. Statements (Months 7–9: closing, 6 FS, notes, consolidation) → gate: full-year FS matches manual FS. Rollout (Months 9–12+: offline PWA, more LGUs, training) → gate: COA/DILG endorsement.

The gates are the acceptance tests: a phase is done only when the pilot's C/M Accountant and Barangay Treasurer can produce the month (or year) from the system alone.

**Phase 0 – Foundation (month 1)**

- [ ] Choose the pilot: one city/municipal accountant willing to co-design, plus 2–3 barangays of different sizes (ideally one with a public market or livestock so DBC and biological-asset flows get tested).
- [ ] Confirm with the COA regional office that the November 2018 manual is the version in force and collect any later circulars amending the chart or forms.
- [ ] Turn this document into the written spec Claude Code will build from: the Chart of Accounts as a CSV (section 3), the 43 forms with fields (section 5), the posting rules (section 7), the system rules (section 8).
- [ ] Create the Supabase project, the Vercel project and a Google Drive folder structure (LGU / barangay / year / month).
- [ ] Seed master data for the pilot: officials, funds, bank account, OR booklet serials, suppliers, employees, opening balances from the last post-closing trial balance.

**Phase 1 – Barangay cash module (months 2–3)**

- [ ] Official Receipt issuance with serial control and cancelled-OR handling; RCR for deputized collectors; RCD generation; deposit slip capture.
- [ ] Cashbook (Annex 8) with its four sections and daily balances; Disbursing Officer cashbook (8.1).
- [ ] DV workflow with Boxes A–E as approval steps, check register, PB Certification printout.
- [ ] RAAF and the monthly Transmittal Letter package as one-click PDFs to Drive.
- [ ] Gate: one calendar month run in parallel with paper; totals match.

**Phase 2 – Budget control and books of accounts (months 3–5)**

- [ ] Appropriation ordinance entry, RAO per fund, obligation certification on PO/DV/Payroll with hard stop, SAOB; REAI; RSTF.
- [ ] Posting engine: automatic draft entries from RCD, RBDCM, DVs, LRs; JV screen; JCT, GJ, GL, SL printouts; period close.
- [ ] Bank memo import and Bank Reconciliation Statement.
- [ ] Accountant console across all barangays of the LGU, with the submission calendar (5th, 10th, 15th working day, 20th, 30 days, 60 days, 10 January) and overdue flags.
- [ ] Gate: the C/M Accountant certifies a month's JCT, GJ, GL and BRS printed from the system.

**Phase 3 – Payroll, cash advances, petty cash, property (months 5–7)**

- [ ] Payroll with deductions and Due to BIR/GSIS/Pag-IBIG/PhilHealth; cash advance ledger with due dates and the no-second-advance rule; Liquidation Reports.
- [ ] Petty cash fund, PCV two-stage form, Petty Cash Record, SPCD and replenishment DV.
- [ ] PR → PO → AIR chain; stock cards with moving average; RIS, ICS, SSMI and the month-end inventory expense JV.
- [ ] PPE register (PEC + PELC), PAR with 3-year renewal reminders, depreciation run, RRPE/IIAR disposal, loss workflow, BAPC and QRBA.
- [ ] Physical count screens producing RIPE and RISM with shortage/overage.
- [ ] Gate: a year-end count and a payroll period reproduced in the system.

**Phase 4 – Statements and year-end (months 7–9)**

- [ ] Adjusting and closing JV routines; pre- and post-closing trial balances.
- [ ] Annexes 34–40 with note numbering, two-year comparatives, Statement of Cash Flows classification, Statement of Comparison from REAI and SAOB; consolidated FS for the LGU; COA digital copies.
- [ ] Gate: the pilot's full-year FS from the system agrees with the Accountant's manually prepared FS.

**Phase 5 – Rollout (months 9–12 and beyond)**

- [ ] Offline-capable PWA for treasurers, Android wrapper on the Play Store, SMS/e-mail reminders for deadlines.
- [ ] Onboarding kit per LGU: opening-balance import, user training (BT, CCA, PB, bookkeeper), printed quick guides in Filipino/Cebuano.
- [ ] Pricing per LGU rather than per barangay (the city or municipality is the buyer: its Accountant benefits most and can procure under RA 9184).
- [ ] Seek a DILG/COA regional endorsement or at least an audit team's written acceptance of system-generated annexes; explore data exchange with LGUSS-BIMS.

What this asks of you personally: own the spec and the pilot relationship (you understand the barangay side from running a business that deals with barangay permits and fees), use Claude Code for the build the way you did for the booking app, and recruit one government accountant (a retired or practising C/M Accountant or COA auditor) as a paid reviewer of every posting rule and every annex layout before the pilot sees it.

## Risks, compliance points and open questions

| Risk or point | Why it matters | What to do |
| --- | --- | --- |
| Manual version | The PDF is dated November 2018 and built on COA Office Order 2014-648; COA issues amendments by circular and the chart may have been revised since | Get the prescribing circular and any later issuances from the COA regional office before seeding the chart; keep the chart versioned by effectivity date in the system |
| Acceptance of system printouts | COA auditors receive the annexes as signed paper; a layout that differs from the annex can be rejected | Reproduce the annex layouts exactly (titles, columns, certification boxes); pilot with the audit team leader who covers the barangays |
| Who the buyer is | Barangays have small budgets; the C/M Accountant's office is the one that benefits most and procures under RA 9184 | Sell per LGU, price within small-value procurement thresholds, and offer the barangay side free within the LGU licence |
| DILG LGUSS-BIMS | DILG is pushing a nationwide barangay system that reportedly includes financial transactions; overlap could block adoption | Find out exactly what its finance sub-system covers and whether it serves the Accountant's books; position your product as the accounting back end and offer data exchange |
| Connectivity and devices | Many barangays have weak internet and share one phone or PC | Offline-first capture for OR, Cashbook and RIS, syncing when online; printable fallbacks |
| Accountable forms are physical | ORs (Accountable Form 51), cash tickets and checks are pre-numbered paper issued by the C/M Treasurer | The system records serials and controls sequence but cannot replace the paper OR unless COA authorizes electronic ORs; design for both |
| Data protection | Payroll, TINs, suppliers and officials' details are personal data under the Data Privacy Act | Role-based access, encryption at rest, audit log, a privacy notice; register as needed with the National Privacy Commission |
| Legal liability of officials | Article 218 of the Revised Penal Code and the manual make the PB and BT personally liable for late or missing accounts | Deadline reminders and a submission log give officials proof of timely rendition; never let the system silently skip a report |
| Opening balances | Most barangays will migrate mid-life with unreconciled property and cash records | Build an opening-balance import with a reconciliation worksheet and allow Prior Years' Adjustments entries |
| Scope creep | Budget preparation (DBM/DILG forms), procurement (PhilGEPS), and the C/M Treasurer's own books are adjacent and tempting | Keep phase 1–4 to what the manual prescribes; treat budget preparation and procurement as later modules |
| Accounting expertise | You are not an accountant; posting rules must be right the first time | Retain a government accountant as reviewer; use the manual's illustrative entries as test cases for the posting engine |

Open questions to settle before Phase 1:

- [ ] Which COA circular prescribes the manual and have the Chart of Accounts or any annex been amended since 2018?
- [ ] Which city or municipality will pilot, and does its Accountant agree to certify system-generated books in parallel with paper for one year?
- [ ] What does LGUSS-BIMS already record for barangay finance, and is there an export or API?
- [ ] Will the pilot's depository bank (Landbank or DBP) provide statements as CSV, or will bank memos be keyed in?
- [ ] Should Phase 1 include the payroll module, given honoraria are most barangays' largest recurring payment?
- [ ] Do you want the budget preparation forms (annual and supplemental budget, which precede the Appropriation Ordinance) in scope, or only what the manual covers from the ordinance onward?

Sources: the attached COA Manual on the Financial Management of Barangays (Chapters I–XIV, Appendices A–C, Annexes 1–43); [DILG Calabarzon on LGUSS-BIMS adoption, 27 Dec 2025](https://calabarzon.dilg.gov.ph/dilg-pushes-full-digital-shift-in-barangays-through-nationwide-lguss-bims-adoption/); connector availability from the claude.ai connector directory as of 28 Oct 2026.
