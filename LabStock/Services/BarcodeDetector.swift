import Foundation
import UIKit
import Vision

/// Native on-device barcode decoding from a captured photo (runs alongside AI analysis).
/// A native result always wins over the model's transcribed barcode text.
enum BarcodeDetector {
    static func detect(in image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else { return nil }
        return await withCheckedContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, _ in
                let observations = (request.results ?? []).sorted { $0.confidence > $1.confidence }
                let payload = observations
                    .compactMap { $0.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty }
                continuation.resume(returning: payload)
            }
            request.symbologies = VNDetectBarcodesRequest.supportedSymbologies
            request.usesCPUOnly = false
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
