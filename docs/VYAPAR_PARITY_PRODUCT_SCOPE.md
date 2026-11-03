# SRK Business Manager — Vyapar-Parity Product Scope and Release Checklist

## Product objective
Build a complete offline-first business management and GST accounting product for Android and Windows, with breadth comparable to Vyapar for everyday workflows, using SRK's own design and architecture. This is a delivery checklist, not a claim that every feature is implemented.

## Verified baseline (3 November 2026)
Existing feature entry points: dashboard, invoices, purchases, products, parties and party ledger, payments, expenses, accounting accounts, warehouses and warehouse stock balance, sales returns, debit notes, reports, GSTR-3B ITC, staff, team access, sync status, authentication/workspace selection and settings. Automated tests cover accounting services, GST calculation/return classification/ITC, ledger reconciliation, inventory costing/valuation, invoice numbering, payment reconciliation, debit notes and sync-role policy. Windows + Android cloud-build workflow exists. Prior main build and UI-refresh PR #14 CI passed; neither proves production readiness or real-device acceptance.

## Status definitions
- Existing foundation: page/service/test exists; end-to-end completeness remains to be reviewed.
- Partial / verify: supporting code exists but workflow, persistence, permissions, reporting or sync is not fully verified.
- Pending: no sufficient implementation evidence in reviewed entry points.
- Release gate: automated tests/builds plus real Android and Windows acceptance tests.

## Feature checklist

### 1. Company onboarding and workspace
- [ ] Full first-time company registration wizard, replacing the minimal three-field popup.
- [ ] Trade/legal name, entity type, owner/contact, email, phone, registered/principal address, PAN and optional registration IDs.
- [ ] GST registration type, GSTIN/state validation; unregistered/composition/regular modes only when tax calculations support them.
- [ ] Financial year, currency, locale, date/number formats and language.
- [ ] Invoice numbering, default terms, logo/signature and print preferences.
- [ ] Inventory defaults, units and godown setup.
- [ ] Staff roles and access setup.
- [ ] Backup/cloud/sync setup with clear optional/required status.
- [ ] Persist settings locally and remotely with migrations, validation and backward compatibility.
- [ ] Existing businesses and historic records remain intact.

### 2. Sales and receivables
- [ ] Tax invoice, bill of supply where applicable, estimate/quotation, proforma and delivery challan.
- [ ] Sales return, credit note, cancellation, duplicate, print and share workflows.
- [ ] Discounts, shipping/other charges, tax-inclusive/exclusive pricing.
- [ ] Cash/bank/UPI/split payments, due dates, credit limits and outstanding.
- [ ] PDF/print templates, invoice numbering and sharing.
- [ ] Sales register and item/party reports with audit trail.

### 3. Purchases and payables
- [ ] Purchase bills, purchase orders and purchase returns.
- [ ] Supplier debit/credit notes and payment allocation.
- [ ] Separate taxable value and tax components.
- [ ] Domestic purchase, import of goods/services, reverse charge and eligible/ineligible ITC.
- [ ] Purchase register, supplier balances and reconciliation.

### 4. Inventory and products
- [ ] Products/services, categories, SKU/barcode, HSN/SAC, units and alternate units.
- [ ] Opening stock, adjustments, transfers and multiple godowns.
- [ ] Batch/expiry/serial tracking where required.
- [ ] Low-stock alerts, reorder levels and stock valuation.
- [ ] Invoice-linked stock movement and returns reconciliation.

### 5. Accounting
- [ ] Chart of accounts and opening balances.
- [ ] Cash/bank, receipts, payments, contra and journal vouchers.
- [ ] General/party ledger, day book and trial balance.
- [ ] Profit & Loss, Balance Sheet and cash-flow reports.
- [ ] Automatic entries reconcile with invoices, returns, taxes and payments.
- [ ] Financial-year closing and audit-safe correction flows.

### 6. GST and statutory reports
- [ ] GST registration configuration and place-of-supply rules.
- [ ] CGST/SGST/IGST, cess, HSN/SAC summaries and tax invoice validation.
- [ ] GSTR-1 tables, credit/debit notes, exports and applicable CSV/JSON exports.
- [ ] GSTR-3B liability/ITC, import ITC, reverse charge and reconciliation.
- [ ] ITC eligibility, blocked/ineligible ITC, reversals and audit trail.
- [ ] GST reports reconcile to source invoices and purchases.
- [ ] Do not claim direct GSTN filing without authorised integration and tests.

### 7. Parties, expenses and reports
- [ ] Customer/supplier master, contacts, credit limits and balances.
- [ ] Party statements, ageing, reminders and payment history.
- [ ] Expense categories, recurring expenses and attachments.
- [ ] Dashboard KPIs/date filters.
- [ ] Sales, purchase, stock, cash/bank, expense, tax and profitability reports.
- [ ] CSV/PDF export and print.

### 8. Users, security and audit
- [ ] Owner/admin/accountant/sales/viewer roles and granular permissions.
- [ ] Staff activation/deactivation and access revocation.
- [ ] Activity log for sensitive changes and financial corrections.
- [ ] Secure sessions, local data protection and safe error handling.

### 9. Offline, cloud and device continuity
- [ ] Every core workflow works offline.
- [ ] Durable sync queue, retries, conflict handling and visible status.
- [ ] Bidirectional Android/Windows sync for every supported entity.
- [ ] Business profile/settings sync with owner/admin permissions.
- [ ] Multi-device conflict and duplicate prevention tests.
- [ ] User-selected backup location where supported; scheduled backup and restore verification.
- [ ] Never claim sync for entities absent from sync schema/policy.

### 10. Messaging and integrations
- [ ] Invoice/statement sharing via Android share sheet and Windows-supported export/share.
- [ ] WhatsApp/SMS/email only through supported APIs or user-initiated sharing; no promise of automatic delivery without provider setup/consent.
- [ ] Payment reminders with preview and recipient confirmation.

### 11. UI and accessibility
- [ ] Consistent premium 3D-inspired design on Android and Windows.
- [ ] Responsive mobile navigation and desktop sidebar/table layouts.
- [ ] Bengali/English, readable typography and accessible contrast.
- [ ] Loading, empty, validation, offline, sync-error and success states.
- [ ] Every visible control performs a real action.

## Release gates
1. Audit schema and architecture before onboarding fields or new toggles.
2. Test migrations from fresh install and all supported database versions.
3. Unit, repository, widget and integration tests pass.
4. Android release APK and Windows x64 package build from the same reviewed commit.
5. Install and smoke-test on real Android and Windows 11 devices.
6. End-to-end test: company setup → opening balances/stock → purchase → sale → payment → return/credit note → GST reports → backup/restore → second-device sync.
7. Independently reconcile totals before calling accounting/GST production-ready.

## Progress reporting
Count a module complete only when its data model, validation, persistence, permissions, offline behaviour, sync (where applicable), reports and tests are verified. Percentage is an estimate until acceptance testing is executed.
