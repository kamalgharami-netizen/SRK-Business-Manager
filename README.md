# SRK Business Manager — Phase 1 Foundation

Original Flutter foundation for a new Windows + Android business accounting application. This repository is independent of SRK Case Manager.

## Current scope
- Flutter application shell and dashboard
- Windows and Android targets
- Supabase configuration through --dart-define
- Feature-module navigation placeholders
- Initial multi-company PostgreSQL schema with membership and Row Level Security
- Separate offline SQLite database for each selected cloud business
- Business-scoped backup folders and database-identity validation during restore
- Durable local sync queue with retry tracking
- First-stage two-way cloud sync for parties and products (requires migration 0003)

## Important
This is a foundation, not a finished accounting product. Do not use it for live bookkeeping, GST filing, or statutory reporting until the remaining modules, validations, tests, backup/restore, and security review are complete.

## Prerequisites
- Flutter SDK (stable)
- Android Studio + Android SDK
- Visual Studio 2022 with Desktop development with C++ workload (Windows builds)
- A Supabase project

## Create the Flutter project
In PowerShell:
```powershell
flutter create --platforms=android,windows srk_business_manager
cd srk_business_manager
```
Copy the `lib/` and `supabase/` folders from this repository into the new Flutter project. Replace `pubspec.yaml` with the supplied file, then run:
```powershell
flutter pub get
flutter doctor
```

## Configure Supabase
1. Create a new Supabase project.
2. Open SQL Editor and run `supabase/migrations/0001_initial_schema.sql`, then `0002_auth_membership_policy_fix.sql`, then `0003_business_records_sync.sql`.
3. Copy the Project URL and publishable key from Supabase project settings.
4. Run on Windows:
```powershell
flutter run -d windows --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```
For Android, enable USB debugging and run:
```powershell
flutter run -d android --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```
The app launches in local demo mode without credentials. When Supabase credentials are configured, the app shows email/password sign-up and sign-in, followed by a basic business list and company-creation screen. If email confirmation is enabled in Supabase Auth, users must confirm their email before signing in. Do not put a Supabase service-role key in the app; use only the project publishable key. Authentication and business membership are connected. Each selected cloud business now opens a separate offline SQLite database under its own business ID; the original device-local database is preserved and is not automatically moved. Backups are stored in separate local/business folders, and restore validation rejects a backup whose business identity does not match the active database. The first cloud-sync stage now uploads and downloads parties and products through the business-scoped `business_records` table. Local edits are added to the durable queue in the same SQLite transaction as the edit; failed uploads remain queued with retry information. Pull skips records that still have pending local changes. Invoices, payments, purchases, expenses, stock movements, staff, full conflict resolution, and production-scale incremental sync are not yet implemented. The current pull reads the supported cloud records in pages and reconciles them on each sync.

## Build
```powershell
flutter build windows --release --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
flutter build apk --release --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

## Planned implementation sequence
1. Foundation, tenant schema, authentication and company setup
2. Offline SQLite repository (per-business database isolation added), durable sync queue integration and conflict handling
3. Parties, products, units, warehouses and stock ledger
4. Sales, estimates, invoices, returns and PDF/thermal printing
5. Purchase, expenses, receipts, payments and cash/bank books
6. Double-entry accounting, trial balance, P&L and balance sheet
7. GST engine, HSN/SAC, tax summaries, GSTR reports and validation
8. Barcode, staff roles, audit logs, backup/restore and reports
9. Automated tests, security review and release builds
