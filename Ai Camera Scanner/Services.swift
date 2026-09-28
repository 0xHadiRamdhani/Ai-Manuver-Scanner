import Foundation
import Vision
import UIKit

enum ScanAnalysis {
    static func recognizeText(in image: UIImage, language: String) async throws -> String {
        guard let cgImage = image.cgImage else { throw AnalysisError.invalidImage }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let lines = (request.results as? [VNRecognizedTextObservation] ?? []).compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            do {
                let supported = try request.supportedRecognitionLanguages()
                let prefersIndonesian = language == "id-ID"
                let requested = language == "Automatic" ? ["id-ID", "en-US"] : [language]
                let available = requested.filter(supported.contains)
                // Indonesian text uses the Latin script, so the English OCR model
                // can still read its characters when Vision has no Indonesian model.
                let fallback = available.isEmpty ? supported.filter { $0 == "en-US" }.prefix(1).map { $0 } : available
                if !fallback.isEmpty { request.recognitionLanguages = Array(fallback) }
                request.usesLanguageCorrection = !(prefersIndonesian && !supported.contains("id-ID"))
                request.automaticallyDetectsLanguage = language == "Automatic"
                try VNImageRequestHandler(cgImage: cgImage).perform([request])
            }
            catch { continuation.resume(throwing: error) }
        }
    }

    static func recognizeCode(in image: UIImage) async throws -> (String, String)? {
        guard let cgImage = image.cgImage else { throw AnalysisError.invalidImage }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let result = (request.results as? [VNBarcodeObservation] ?? []).first
                continuation.resume(returning: result.flatMap { item in item.payloadStringValue.map { (item.symbology.rawValue, $0) } })
            }
            do { try VNImageRequestHandler(cgImage: cgImage).perform([request]) }
            catch { continuation.resume(throwing: error) }
        }
    }
}

enum AnalysisError: LocalizedError {
    case invalidImage
    var errorDescription: String? { "Unable to read this image. Please try another photo." }
}

protocol AIProvider {
    func respond(to prompt: String, about text: String) async throws -> String
}

/// Secure server-side AI integration point. No provider key is bundled in the app.
struct ProxyAIProvider: AIProvider {
    let endpoint: URL?
    var model: String = ""
    func respond(to prompt: String, about text: String) async throws -> String {
        guard let endpoint else { throw URLError(.badURL) }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["prompt": prompt, "text": text, "model": model])
        let (data, _) = try await URLSession.shared.data(for: request)
        let result = try JSONDecoder().decode(AIResponse.self, from: data)
        return result.text
    }
    private struct AIResponse: Decodable { let text: String }
}
