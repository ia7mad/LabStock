# LabStock setup

LabStock uses the live Supabase project as its backend. `Config.xcconfig` is already
populated with the project URL and publishable key through the existing
configuration system, which feeds `SupabaseURL` / `SupabasePublishableKey` in
`Info.plist`. Only publishable keys belong in the app — never a secret or
`service_role` key.

1. `supabase/migrations/20261007000100_labstock.sql` is production **documentation**:
   it mirrors the live schema (tables, RLS, `apply_stock_delta`,
   `complete_inventory_session`, and the Realtime publication). Do not run it
   against the live project.
2. Confirm Email/Password auth and Realtime replication are enabled in the
   Supabase dashboard.
3. Open `LabStock.xcodeproj` in Xcode 26+, choose an iPhone running iOS 16+,
   select your development team, then Build/Run. Run tests with Product → Test.

Scheduled stock changes always go through `apply_stock_delta`; the client never
writes `batches.current_quantity` directly.

## AI label scanning

Scanning is AI-first: one camera photo is sent to the DeepSeek vision model
(`deepseek-flash`) which returns strict JSON with the reagent name, REF/catalog
number, LOT, expiry, pack size and storage. On-device Vision barcode decoding and
Apple OCR run in parallel as hints — a native barcode always wins over the
model's transcribed text. Recognized barcodes/REF values are stored as
`scan_aliases` so later scans skip the AI lookup.

`DEEPSEEK_MODEL` lives in `Config.xcconfig`; the real `DEEPSEEK_API_KEY` is kept
in a git-ignored `Config.local.xcconfig` that `Config.xcconfig` includes, so the
key is never committed (GitHub push protection also blocks leaked keys). Both
values reach the app through `Info.plist` (`DeepSeekAPIKey`, `DeepSeekModel`).
The key is never logged.

## CI

`.github/workflows/ci.yml` builds the generic iOS device target with code
signing disabled, packages `Payload/LabStock.app` into `LabStock.ipa`, uploads
it as a build artifact, and runs the XCTest suite on an available iPhone
simulator. No signing credentials are required.

