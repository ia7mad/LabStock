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

## CI

`.github/workflows/ci.yml` builds the generic iOS device target with code
signing disabled, packages `Payload/LabStock.app` into `LabStock.ipa`, uploads
it as a build artifact, and runs the XCTest suite on an available iPhone
simulator. No signing credentials are required.

