# Production acceptance runbook

This runbook is the controlled final-verification procedure for SRK Business Manager. It complements the automated GitHub build; it does not claim that live Supabase, multi-device, GSTN, or disaster-recovery tests have already passed.

## 1. Release build evidence

The GitHub Actions workflow must complete both jobs successfully:

- Android Release APK
- Windows Release Package

Download both artifacts from the same successful run. Keep the run URL, commit SHA, artifact names, and test date in the release record. A successful CI build proves that the configured analyzer/tests/build steps passed; it does not prove that cloud credentials, RLS, device installation, or GST statutory outputs work.

## 2. Supabase schema deployment

1. Create/select the dedicated Supabase project for SRK Business Manager. Do not use a different application's project.
2. Inspect the live schema and migration history first. Apply only migrations not already deployed, in numerical order from `0001_initial_schema.sql` through `0016_incremental_sync_cursor_index.sql`. The current repository sequence includes:
   - `0014_warehouse_transfer_sync.sql`
   - `0015_extended_business_onboarding.sql`
   - `0016_incremental_sync_cursor_index.sql`
3. Do not blindly paste all migrations into a project that may already contain some of them. Resolve any partial/failed migration before continuing. In particular, migrations 0014–0016 must be checked against the actual deployed schema before execution.
4. Run [the read-only migration 0014 checks](../supabase/verification/0014_post_migration_checks.sql) and [the read-only migration 0015 checks](../supabase/verification/0015_post_migration_checks.sql).
5. Run [the read-only migration 0016 checks](../supabase/verification/0016_post_migration_checks.sql). Confirm the incremental pull index exists with the expected column order.
6. Confirm `public.business_records` has RLS enabled, all intended policies and constraints exist, and server-side role functions/grants match the migration definitions.
7. Add only `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` as GitHub Actions secrets if cloud builds are required. Never expose the service-role key in the client app, repository, or build logs.

**Pass condition:** all schema checks return the expected objects and no migration errors remain. A SQL Editor query alone does not prove RLS behavior.

## 3. Authenticated RLS role matrix

Use five separately authenticated test accounts in one disposable test business: owner, admin, accountant, sales, and viewer. Test through the app/client using each account's real session; do not use the SQL Editor's elevated session as an RLS test.

| Entity / operation | Owner | Admin | Accountant | Sales | Viewer |
|---|---:|---:|---:|---:|---:|
| parties, products | Write | Write | Write | Write | Deny |
| expenses | Write | Write | Write | Deny | Deny |
| invoices, payments | Write | Write | Write | Write | Deny |
| payment_allocations | Write | Write | Write | Write | Deny |
| stock_movements | Write | Write | Write | Deny | Deny |
| business_profile, staff_members, warehouses, warehouse_transfers | Write | Write | Deny | Deny | Deny |

For every denied operation, confirm the server rejects the write and the local queue reports/retains the failure safely. Also verify that a user cannot read or write another business's records.

**Pass condition:** every matrix cell behaves as specified on the server, not merely in the UI.

## 4. Two-device synchronization

Use two physical devices or a physical device plus a separate Windows installation. Sign both into the same test business with appropriate accounts. Start with a fresh test dataset and record device IDs/build versions.

1. Create a party and product on device A; sync; confirm device B receives each once.
2. Create a purchase invoice on A; sync; confirm B receives invoice lines, FIFO purchase-cost layers, and the expected journal entry.
3. Create a sales invoice, receipt/payment, and invoice allocation; sync; confirm party ledger, invoice paid balance, allocation, and journal totals on B.
4. Create a purchase return and sales return; confirm source links, warehouse assignment, FIFO effects, and accounting entries.
5. Create a stock adjustment, warehouse transfer, and legacy/unassigned-stock allocation; sync each to B and reconcile quantities, FIFO costs, estimated-cost flags, and movement history.
6. Repeat sync on both devices without making changes. No duplicate records, journal postings, stock movements, or quantity increments may appear.
7. Edit the same record on both devices before syncing. Confirm optimistic conflict detection, explicit resolution, and preservation of the chosen value.
8. Disable network on A, create edits, re-enable network, sync, and confirm queued changes upload once.
9. Delete/deactivate supported records and verify tombstones/active status are reconciled as designed.
10. Repeat with larger datasets and interrupted connections; record sync duration, queue failures, and retry behavior.

**Pass condition:** all data, ledgers, stock/FIFO values and revisions reconcile on both devices; no silent data loss or duplicate posting occurs.

## 5. GST statutory validation

The current GSTR-1 invoice-classification CSV and HSN/SAC CSV are spreadsheet-friendly management/review reports. They are **not** GSTN upload JSON and must never be labelled as filing-ready exports. The GSTR-1 preflight is also a preparation control, not proof of GSTN filing compliance. GST Portal guidance describes preparing GSTR-1 online or uploading JSON prepared through the official offline tools: [GST Portal - Creation of Outward Supplies Return in GSTR-1](https://tutorial.gst.gov.in/userguide/returns/Creation_of_Outward_Supplies_Return_in_GSTR-1.htm).

1. On the GST Portal, obtain the current official Returns Offline Tool and its bundled instructions/schema for the exact return period being tested. Record the download date, displayed tool version, schema/template version (if separately stated), and source URL in the acceptance evidence. Do not infer the version from third-party download pages or copy an unverified third-party JSON schema into the app.
2. Prepare representative cases: B2B, B2C large/small, credit/debit notes, exports/SEZ, advances, amendments, nil/exempt/non-GST, e-commerce and HSN summary as applicable.
3. Validate invoice-level taxable values and tax components, place of supply, GSTIN, return period, document numbering, rounding, and ITC eligibility/reversals/RCM.
4. Until a dedicated GSTN JSON exporter has been implemented and independently tested, use the app's CSV files only as review/import inputs for the official offline utility where that utility supports the relevant template. Do not upload these management CSV files as JSON.
5. If/when a GSTN JSON exporter is implemented, compare its output against the official offline tool and its validation results. Resolve every error/warning and retain the exact sanitized sample JSON, tool/schema version, validation result, and sample dataset in the acceptance evidence. Do not store taxpayer credentials or live taxpayer data in the repository.
6. Do not file live returns from this app until an independent GST practitioner review and successful official-tool validation are recorded.

**Pass condition:** the exact supported output passes the current official GSTN tool/schema validation for the relevant return period. Unsupported return categories must remain clearly identified as unsupported.

## 6. Backup and restore / disaster recovery

1. Create a local backup with a known test business and record the database version, business identity, and file size.
2. Restore into a clean test installation and verify business identity, parties, products, invoices, invoice lines, payments, allocations, journals, FIFO layers, warehouses, and reports.
3. Test a wrong-business backup and a corrupted/incomplete backup; restore must reject safely without overwriting the current business.
4. Test backup copy to a separate physical/off-device location. A backup stored only on the same PC is not disaster recovery.
5. Simulate loss of the original installation and restore from the off-device copy. Record recovery time and data-loss window.
6. Confirm cloud sync can repopulate a clean second device after authentication, without duplicating records.

**Pass condition:** successful restore and reconciled accounting/inventory on a clean device, plus a verified off-device copy and documented recovery procedure.

## 7. Windows and Android user acceptance

- Windows 11: install/extract the complete ZIP package, launch the EXE, restart, and verify local database persistence, printing/export, backup/restore, and no missing runtime files.
- Android: install the APK on a supported device, launch, restart, verify storage/permissions, offline workflows, network recovery, and background/foreground behavior.
- Verify business registration, authentication, role-based navigation, invoices, returns, payments, GST reports, stock, warehouses, reports, and backup.
- Record device model/OS, app commit/build, tester, date, defects, and pass/fail evidence.

**Production sign-off requires all sections 2–7 to pass.** Until then, label the build as a test/beta build and do not rely on it for statutory filing or live accounting.
