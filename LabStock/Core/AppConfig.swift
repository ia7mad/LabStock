import Foundation

enum AppConfig {
    private static var rawURL: String { Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String ?? "" }
    private static var rawKey: String { Bundle.main.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String ?? "" }
    private static var rawDeepSeekKey: String { Bundle.main.object(forInfoDictionaryKey: "DeepSeekAPIKey") as? String ?? "" }
    private static var rawDeepSeekModel: String { Bundle.main.object(forInfoDictionaryKey: "DeepSeekModel") as? String ?? "" }

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

    /// DeepSeek vision key. Never log this value.
    static var deepSeekAPIKey: String? {
        let key = rawDeepSeekKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sk-"), !key.contains("YOUR_"), key.count > 12 else { return nil }
        return key
    }

    static var deepSeekModel: String {
        let model = rawDeepSeekModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? "deepseek-flash" : model
    }

    static var deepSeekBaseURL: URL { URL(string: "https://api.deepseek.com")! }

    /// Small LOT/EXP/REF text needs full-resolution analysis.
    static let deepSeekImageDetail = "original"

    static var isDeepSeekConfigured: Bool { deepSeekAPIKey != nil }
}
