import Foundation
import SwiftData

enum ScanType: String, Codable, CaseIterable, Identifiable {
    case document, text, qr, barcode, object
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self { case .document: "doc.text"; case .text: "text.viewfinder"; case .qr: "qrcode"; case .barcode: "barcode.viewfinder"; case .object: "viewfinder" }
    }
}

@Model final class ScanItem {
    var id: UUID
    var type: ScanType
    var title: String
    var content: String
    var createdAt: Date
    var thumbnailData: Data?
    var confidence: Double?
    var metadata: String

    init(type: ScanType, title: String, content: String, thumbnailData: Data? = nil, confidence: Double? = nil, metadata: String = "") {
        self.id = UUID(); self.type = type; self.title = title; self.content = content
        self.createdAt = .now; self.thumbnailData = thumbnailData; self.confidence = confidence; self.metadata = metadata
    }
}
