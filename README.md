# SRK Business Manager

Offline-first GST billing and accounting application for Windows and Android. This repository is independent of **SRK Case Manager**.

## Current implementation status

The repository contains a working Flutter application foundation and feature modules for:

- Business registration, sign-in, company workspace and separate local SQLite database per selected cloud business
- Parties, products, sales invoices, estimates, sales returns, purchase invoices and purchase returns
- Expenses, receipts and payments
- Inventory quantities, stock adjustments and FIFO inventory-cost layers
- Double-entry journal posting, chart of accounts, trial balance, profit & loss and balance sheet
- GST invoice tax calculation fields, HSN/SAC, place of supply and tax summaries
- Staff profile management (local profiles) and cloud business-user access roles
- Local database backup and restore with business-identity validation
- Durable offline sync queue, retry scheduling, optimistic cloud revision checks and a conflict-resolution screen
- First-stage two-way cloud sync for parties, products, expenses, invoices (including purchase/sales invoices and returns), payments and stock movements

**This is not yet a finished production accounting or statutory GST product.** Do not rely on it for live bookkeeping, GST returns/filing, statutory submissions or tax compliance until the remaining accounting, GST, sync, security and device-level acceptance tests have been completed.

## Implemented sync limitations

- Purchase invoices and their line items can be transferred as invoice records. Downloading a purchase invoice does not yet recreate its accounting journal, FIFO cost layers or inventory valuation on the receiving device.
- Stock movements and product quantity snapshots sync separately. The receiver does not replay movement deltas, to avoid double-counting during repeated pulls.
- Cloud sync currently performs paged reconciliation of supported records; production-scale incremental sync and broader entity coverage remain pending.
- Staff profiles are local records. Cloud login accounts and the role-based permissions in the Team & Access screen are separate concepts.
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

1. Complete accounting-ledger replication for cloud-downloaded purchase invoices, purchase returns, payments and inventory-cost layers; add reconciliation checks for cross-device balances.
2. Complete the GST engine and statutory reports, including validated GSTR-1 / GSTR-3B data exports and tax-period controls. Independently verify all tax calculations against current official GST rules before release.
3. Add cloud sync for remaining business data (including staff profiles where appropriate), company settings, warehouses and other inventory records.
4. Improve incremental sync, large-dataset performance, conflict recovery and end-to-end multi-device tests.
5. Complete role/permission tests, audit trails, security review and backup/restore disaster-recovery tests.
6. Expand automated tests for invoice workflows, purchase workflows, GST edge cases, reports, database migrations and Windows/Android device behavior.
7. Perform user acceptance testing on real Windows 11 and Android devices before publishing a production release.

## Important accounting and tax notice

This application is under active development. A successful CI build confirms that the current source passes the configured analyzer/tests and that the Windows and Android packages can be built; it does **not** certify accounting correctness, GST compliance, security or production readiness.
