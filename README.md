# SRK Business Manager

Offline-first GST billing and accounting application for Windows and Android. This repository is independent of **SRK Case Manager**.

## Current implementation status

The repository contains a working Flutter application foundation and feature modules for:

- Business registration, sign-in, company workspace and separate local SQLite database per selected cloud business
- Parties, products, sales invoices, estimates, sales returns, purchase invoices and purchase returns
- Expenses, receipts and payments
- Inventory quantities, stock adjustments and FIFO inventory-cost layers
- Double-entry journal posting, chart of accounts, trial balance, profit & loss and balance sheet
- Centralised GST line calculation with paise rounding, intra-state CGST/SGST and inter-state IGST allocation, HSN/SAC and place-of-supply fields
- GSTR-1 preflight validation in GST Reports for selected-period outward sales invoices, supplier/recipient GSTIN format, invoice dates and duplicates, place of supply, line items, HSN/SAC warnings and taxable/tax values; this is a preparation aid only, not a GSTN upload file or filing-ready return
- Staff and warehouse master-data management with owner/admin-only two-way cloud sync, separate from cloud login accounts and business-user access roles
- Local database backup and restore with business-identity validation
- Durable offline sync queue, retry scheduling, optimistic cloud revision checks and a conflict-resolution screen
- Two-way cloud sync for the business profile, staff profiles and warehouse master records (owner/admin only), parties, products, expenses, invoices (including purchase/sales invoices and returns), payments, payment allocations and stock movements
- Linked receipt/payment reconciliation on cloud download, with party/invoice type validation, invoice paid-balance reconciliation that avoids duplicate counting, and idempotent journal posting

**This is not yet a finished production accounting or statutory GST product.** Do not rely on it for live bookkeeping, GST returns/filing, statutory submissions or tax compliance until the remaining accounting, GST, sync, security and device-level acceptance tests have been completed.

## Implemented sync limitations

- Downloading a new purchase invoice now recreates its local invoice lines, FIFO purchase-cost layers and purchase-invoice journal entry on the receiving device. Existing purchase invoices are treated as immutable during reconciliation so their local cost-layer references are not rebuilt.
- Purchase and sales invoices and their returns are now included in invoice sync. The current workflow reconstructs source-linked FIFO costs and accounting journals for these transaction types on receiving devices. This has passed the configured CI analyzer, automated tests and Windows/Android build jobs; broader real-device multi-device reconciliation remains pending.
- Product quantity snapshots sync separately and are not incremented by replayed movement deltas. Stock-adjustment FIFO effects and legacy-stock allocations are replayed atomically with their first movement insert; warehouse transfers use a dedicated atomic transfer entity. Repeated pulls are idempotent.
- Cloud sync now uses per-entity keyset pulls ordered by `(updated_at, record_id)`, with a frozen timestamp boundary per pass, persistent local checkpoints, inclusive timestamp overlap to catch same-timestamp inserts, and retry-from-last-success behavior when a row cannot be applied. The first pull for each entity is a full paged sync; later pulls resume from the saved timestamp boundary. Migration 0016 supplies the matching composite index. Tombstone application and real concurrent two-device behavior still require integration validation against the configured Supabase project. The client-side write policy is centralized in `BusinessSyncEntityPolicy` and tested against the supported entity list; unresolved cloud roles fail closed. Database-side role enforcement remains dependent on applying the Supabase migrations.
- Business profile fields, staff profiles and warehouse master records sync bidirectionally for business owners/admins. Warehouse names and codes are unique per local business database; deactivate records rather than deleting a warehouse. Stock adjustments now select an active warehouse and constrain FIFO cost-layer additions/removals to that warehouse; other-warehouse and unassigned stock cannot silently cover a warehouse shortage. Staff profile labels remain separate from cloud login accounts and role-based permissions in the Team & Access screen.
- Database version 33 adds stable `warehouse_sync_id` reference columns and lookup indexes to invoices, stock movements and FIFO cost layers, plus durable warehouse-transfer and stock-adjustment FIFO-effect data. Purchase/sales invoices and stock adjustments are assigned to warehouses, with FIFO consumption scoped to the selected warehouse. The Warehouse Stock Balance report shows per-warehouse quantities and FIFO value and separates legacy/unassigned stock. Warehouse transfers preserve source FIFO costs and estimated-cost flags; their atomic cloud record replays both sides and movement history. The controlled legacy allocation screen moves only unassigned FIFO layers to an active warehouse, preserves cost metadata and syncs an atomic allocation effect. Supabase migrations 0014–0015 and real two-device validation must be applied/verified in the target Supabase project before cloud production use. Stable cloud IDs avoid relying on device-local SQLite row IDs.
- A team member must already have registered for a cloud account before an owner/admin can add that account to a business. The current flow does not send invitation emails.
- The local backup/restore feature does not replace a tested off-device backup and disaster-recovery plan.

## Prerequisites

- Flutter SDK (stable channel; Dart 3.6 or later)
- Android Studio and Android SDK for Android development
- Visual Studio 2022 with **Desktop development with C++** workload for Windows builds
- A Supabase project for cloud authentication, team access and two-way sync (optional for local demo mode)

## Set up the project

Clone or download this repository, then from its root directory run:

```powershell
flutter create --platforms=android,windows --project-name=srk_business_manager .
flutter pub get
flutter doctor
flutter analyze
flutter test
```

The GitHub Actions workflow generates the platform runner files on clean build agents, so generated Android/Windows platform directories do not need to be committed.

## Configure Supabase

Create a dedicated Supabase project for SRK Business Manager. In the Supabase SQL Editor, run these migrations **in numerical order**:

1. `supabase/migrations/0001_initial_schema.sql`
2. `supabase/migrations/0002_auth_membership_policy_fix.sql`
3. `supabase/migrations/0003_business_records_sync.sql`
4. `supabase/migrations/0004_expenses_sync.sql`
5. `supabase/migrations/0005_sales_invoice_sync.sql`
6. `supabase/migrations/0006_payments_sync.sql`
7. `supabase/migrations/0007_stock_movements_sync.sql`
8. `supabase/migrations/0008_team_access_and_permissions.sql`
9. `supabase/migrations/0009_payment_allocations_sync.sql`
10. `supabase/migrations/0010_payment_allocation_role_permissions.sql`
11. `supabase/migrations/0011_business_profile_sync.sql`
12. `supabase/migrations/0012_staff_profile_sync.sql`
13. `supabase/migrations/0013_warehouse_master_data_sync.sql`
14. `supabase/migrations/0014_warehouse_transfer_sync.sql`
15. `supabase/migrations/0015_extended_business_onboarding.sql`
16. `supabase/migrations/0016_incremental_sync_cursor_index.sql`

After applying migration 0015, run `supabase/verification/0015_post_migration_checks.sql` in the Supabase SQL Editor to verify the extended company-profile columns, validation constraints and owner/admin update policy.

In GitHub, open **Settings → Secrets and variables → Actions** and add these repository secrets:

- `SUPABASE_URL`: the Supabase project URL
- `SUPABASE_PUBLISHABLE_KEY`: the Supabase publishable key

Never place the Supabase service-role key in this client application or in GitHub build variables.

If the two secrets are absent, the app builds in local demo mode. To run with cloud access, supply the same values using Dart defines:

```powershell
flutter run -d windows --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

For Android, enable USB debugging and run:

```powershell
flutter run -d android --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

Each selected cloud business uses a separate local SQLite database under that business UUID. The original device-local database is preserved and is not automatically migrated into a cloud business database.

## Build locally

```powershell
flutter build windows --release --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
flutter build apk --release --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

Windows output: `build/windows/x64/runner/Release/` (the EXE and its required runtime files must be distributed together).

Android output: `build/app/outputs/flutter-apk/app-release.apk`.

## GitHub Actions builds

Workflow: `.github/workflows/cloud-build.yml`

Every push to `main`, pull request targeting `main`, or manual workflow dispatch runs Android and Windows jobs. Each job installs Flutter dependencies, runs `flutter analyze` and `flutter test`, builds its release target, and uploads a build artifact. The Windows artifact is a ZIP containing the EXE and its required runtime files; the Android artifact is the release APK.

Check **Actions → SRK Business Manager - Cloud Build** for the latest run and download the artifacts from that successful run. Artifacts are temporary and expire according to the workflow retention setting.

## Remaining work before production release

1. Complete real-device cross-device payment allocation and party-ledger reconciliation tests, including linked and unlinked receipts/payments, concurrent edits, and conflict recovery. The current sync handler validates linked parties/invoices, reconciles invoice paid snapshots against synced allocations, and avoids duplicate payment journal posting; real-device acceptance remains pending.
2. Complete GST statutory reporting and independently validate GSTR-1 / GSTR-3B exports against the current official GSTN offline-tool schema and rules. The GST Reports screen now includes a GSTR-1 preflight check for core outward invoice data, but it does not yet create a GSTN upload JSON file. GSTR-3B preparation still needs GSTR-2B data, eligible/ineligible ITC, reversals and reverse-charge information.
3. Finish end-to-end cloud transfer/allocation validation on two real devices. The Warehouse Stock Balance page now lists legacy/unassigned stock by product and allows a user to allocate a chosen quantity to an active warehouse. Allocation consumes only unassigned FIFO layers, preserves each layer's unit cost and estimated-cost flag, records an audit stock movement, and syncs the exact allocation effect; a receiving device applies it atomically and rejects mismatched legacy FIFO state. Warehouse transfers are now represented by one owner/admin-only cloud record containing both warehouse references, both movement IDs and the exact FIFO cost-layer allocations; a receiving device applies the source deduction, destination receipt and movement history atomically. Replay fails closed if its source FIFO layers do not match the transmitted cost/estimated-cost allocations. Stock adjustments now carry their exact FIFO layer effects in the stock-movement sync payload and replay those effects idempotently on first cloud insert; real two-device validation and applying Supabase migrations 0014–0015 remain pending. The Warehouse Stock Balance report separates assigned balances from legacy/unassigned stock.
4. Improve incremental sync, large-dataset performance, conflict recovery and end-to-end multi-device tests.
5. Dart-side cloud role/permission tests now cover owner, admin, accountant, sales and viewer across all supported sync entities. Apply the matching Supabase migrations and verify database RLS behavior for each role; complete the broader audit-trail, security review and backup/restore disaster-recovery tests.
6. Expand automated tests for invoice workflows, purchase workflows, GST edge cases, reports, database migrations and Windows/Android device behavior.
7. Perform user acceptance testing on real Windows 11 and Android devices before publishing a production release.

## Important accounting and tax notice

This application is under active development. A successful CI build confirms that the current source passes the configured analyzer/tests and that the Windows and Android packages can be built; it does **not** certify accounting correctness, GST compliance, security or production readiness.
