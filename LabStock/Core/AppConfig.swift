import Foundation

enum AppConfig {
    private static var rawURL: String { Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String ?? "" }
    private static var rawKey: String { Bundle.main.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String ?? "" }

    static var isConfigured: Bool {
        !rawURL.contains("YOUR_PROJECT") && !rawKey.contains("YOUR_PUBLISHABLE_KEY")
            && URL(string: rawURL) != nil && !rawKey.isEmpty
    }

    static var supabaseURL: URL {
        URL(string: rawURL) ?? URL(string: "https://example.supabase.co")!
    }

    static var supabaseKey: String {
        rawKey.isEmpty ? "sb_publishable_placeholder" : rawKey
    }
}
