# SRK Business Manager — Phase 1 Foundation

Original Flutter foundation for a new Windows + Android business accounting application. This repository is independent of SRK Case Manager.

## Current scope
- Flutter application shell and dashboard
- Windows and Android targets
- Supabase configuration through --dart-define
- Feature-module navigation placeholders
- Initial multi-company PostgreSQL schema with membership and Row Level Security

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
2. Open SQL Editor and run `supabase/migrations/0001_initial_schema.sql`.
3. Copy the Project URL and publishable key from Supabase project settings.
4. Run on Windows:
```powershell
flutter run -d windows --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```
For Android, enable USB debugging and run:
```powershell
flutter run -d android --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```
The app launches in demo mode without credentials; cloud features are not active until authentication and configuration are completed.

## Build
```powershell
flutter build windows --release --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
flutter build apk --release --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

## Planned implementation sequence
1. Foundation, tenant schema, authentication and company setup
2. Offline SQLite repository, durable sync queue and conflict handling
3. Parties, products, units, warehouses and stock ledger
4. Sales, estimates, invoices, returns and PDF/thermal printing
5. Purchase, expenses, receipts, payments and cash/bank books
6. Double-entry accounting, trial balance, P&L and balance sheet
7. GST engine, HSN/SAC, tax summaries, GSTR reports and validation
8. Barcode, staff roles, audit logs, backup/restore and reports
9. Automated tests, security review and release builds
