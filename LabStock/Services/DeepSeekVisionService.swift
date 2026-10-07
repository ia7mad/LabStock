import CryptoKit
import Foundation
import UIKit

/// One place for every DeepSeek vision request. The API key is read from
/// `Config.xcconfig` (through `Info.plist`) and is never logged.
actor DeepSeekVisionService {
    static let shared = DeepSeekVisionService()

    private let session: URLSession
    /// Prevents duplicate API calls for the same photo inside one scanning session.
    private var cache: [String: ReagentExtraction] = [:]

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 45
            configuration.timeoutIntervalForResource = 90
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    func cachedExtraction(forImageHash hash: String) -> ReagentExtraction? { cache[hash] }

    func clearCache() { cache.removeAll() }

    /// Sends one captured label image to DeepSeek and returns structured fields.
    func analyze(jpegData: Data, imageHash: String) async throws -> ReagentExtraction {
        if let cached = cache[imageHash] { return cached }
        guard let apiKey = AppConfig.deepSeekAPIKey else { throw DeepSeekError.notConfigured }

        var request = URLRequest(url: AppConfig.deepSeekBaseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(
                model: AppConfig.deepSeekModel,
                messages: [
                    .init(role: "system", content: [.init(type: "text", text: DeepSeekPrompt.system)]),
                    .init(role: "user", content: [
                        .init(type: "text", text: DeepSeekPrompt.user),
                        .init(type: "image_url", image_url: .init(
                            url: "data:image/jpeg;base64,\(jpegData.base64EncodedString())",
                            detail: AppConfig.deepSeekImageDetail
                        ))
                    ])
                ],
                temperature: 0,
                response_format: .init(type: "json_object")
            )
        )

        #if DEBUG
        let startedAt = Date()
        #endif

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw DeepSeekError.from(urlError: urlError)
        } catch {
            throw DeepSeekError.invalidResponse
        }

        guard let http = response as? HTTPURLResponse else { throw DeepSeekError.invalidResponse }
        if let error = DeepSeekError.from(statusCode: http.statusCode) { throw error }

        #if DEBUG
        // Debug-only timing. Never logs the key or the image payload.
        print("DeepSeek label request finished in \(String(format: "%.2f", Date().timeIntervalSince(startedAt)))s")
        #endif

        guard let content = ChatResponse.assistantContent(from: data) else { throw DeepSeekError.invalidResponse }
        guard let extraction = DeepSeekExtractionDecoder.decode(content) else { throw DeepSeekError.invalidResponse }
        guard extraction.hasUsefulData else { throw DeepSeekError.noLabelData }

        cache[imageHash] = extraction
        return extraction
    }
}

// MARK: - Wire format

private struct ChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: [ContentPart]
    }
    struct ContentPart: Encodable {
        let type: String
        var text: String?
        var image_url: ImageURL?
    }
    struct ImageURL: Encodable {
        let url: String
        let detail: String
    }
    struct ResponseFormat: Encodable {
        let type: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let response_format: ResponseFormat
}

struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }
    let choices: [Choice]

    /// Extracts the assistant text, tolerating reasoning models that return parts.
    static func assistantContent(from data: Data) -> String? {
        guard let response = try? JSONDecoder().decode(ChatResponse.self, from: data) else { return nil }
        return response.choices.first?.message.content
    }
}

/// Tolerates ```json fences and surrounding prose.
enum DeepSeekExtractionDecoder {
    static func decode(_ content: String) -> ReagentExtraction? {
        guard let json = jsonObject(in: content) else { return nil }
        return try? JSONDecoder().decode(ReagentExtraction.self, from: Data(json.utf8))
    }

    static func jsonObject(in content: String) -> String? {
        var text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```json", with: "```")
            let parts = text.components(separatedBy: "```")
            if parts.count > 1 { text = parts[1] }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return String(text[start...end])
    }
}

enum DeepSeekPrompt {
    static let system = """
    You are a fast laboratory reagent label reader. \
    Read the image and extract only factual inventory fields. \
    Return null when unclear. \
    Never guess REF, LOT, or expiry. \
    Return JSON only.
    """

    /// Compact fast-mode request: only the fields an inventory scan needs.
    static let user = """
    Read this reagent label. Return JSON only, no prose, using exactly these keys:
    {
      "product_name": null,
      "manufacturer": null,
      "reference_number": null,
      "lot_number": null,
      "expiry_date": null,
      "volume_or_pack": null,
      "confidence": 0.0,
      "field_confidence": {
        "product_name": 0.0,
        "reference_number": 0.0,
        "lot_number": 0.0,
        "expiry_date": 0.0
      }
    }
    Rules: read small printed text; REF/catalog number is not the LOT; normalize expiry_date to YYYY-MM-DD when certain; \
    never invent REF, LOT or expiry; return null when a value is unclear.
    """
}

enum DeepSeekError: Error, Equatable {
    case notConfigured
    case offline
    case timedOut
    case unauthorized
    case rateLimited
    case server(Int)
    case invalidResponse
    case noLabelData

    static func from(statusCode: Int) -> DeepSeekError? {
        switch statusCode {
        case 200..<300: return nil
        case 401, 403: return .unauthorized
        case 429: return .rateLimited
        case 400..<500: return .invalidResponse
        default: return .server(statusCode)
        }
    }

    static func from(urlError: URLError) -> DeepSeekError {
        switch urlError.code {
        case .timedOut: return .timedOut
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
             .cannotConnectToHost, .dataNotAllowed, .internationalRoamingOff: return .offline
        default: return .invalidResponse
        }
    }

    var message: String {
        switch self {
        case .notConfigured: "AI label reading is not configured. Add the DeepSeek key to Config.xcconfig."
        case .offline: "You appear to be offline. Check your connection and try again."
        case .timedOut: "The label analysis timed out. Try again with a clearer photo."
        case .unauthorized: "AI label reading is unavailable right now. Use manual entry to continue."
        case .rateLimited: "Too many label scans at once. Wait a moment and try again."
        case .server: "The label service is busy. Try again shortly."
        case .invalidResponse, .noLabelData: "Couldn't read this label. Try moving closer and keeping the label flat."
        }
    }

    var canRetry: Bool {
        switch self {
        case .unauthorized, .notConfigured: false
        default: true
        }
    }
}

/// Resizes, compresses and hashes a captured label image before upload.
enum LabelImage {
    /// Fast-mode upload size: enough detail for small print, small enough to send quickly.
    static let maxDimension: CGFloat = 1600
    static let jpegQuality: CGFloat = 0.78

    static func prepare(_ image: UIImage, maxDimension: CGFloat = maxDimension, quality: CGFloat = jpegQuality) -> (data: Data, hash: String)? {
        let resized = resized(image, maxDimension: maxDimension)
        guard let data = resized.jpegData(compressionQuality: quality) else { return nil }
        return (data, sha256(data))
    }

    static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
