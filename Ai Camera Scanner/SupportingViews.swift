import SwiftUI
import SwiftData
import VisionKit
import PhotosUI
import UIKit
import Vision

struct ScanDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: ScanItem
    @State private var isSaved: Bool
    @AppStorage("haptics") private var haptics = true
    @AppStorage("aiProvider") private var aiProvider = "Server Proxy"
    @AppStorage("aiEndpoint") private var aiEndpoint = ""
    @AppStorage("aiModel") private var aiModel = ""
    @State private var showAIChoices = false
    @State private var showAIResult = false
    @State private var isAnalyzing = false
    @State private var aiMessage = ""
    init(item: ScanItem, isInitiallySaved: Bool) {
        self.item = item
        self.isSaved = isInitiallySaved
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let data = item.thumbnailData, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 20)) }
                    Label(LocalizedStringKey(item.type.title), systemImage: item.type.symbol).font(.subheadline.weight(.semibold)).foregroundStyle(ScannerPalette.accent)
                    TextField("Title", text: $item.title).font(.title2.bold())
                    Text(item.createdAt.formatted(date: .long, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $item.content).frame(minHeight: 180).padding(10).background(ScannerPalette.raised, in: RoundedRectangle(cornerRadius: 12))
                    HStack {
                        ShareLink(item: item.content) { Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                        Button { UIPasteboard.general.string = item.content; if haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() } } label: { Label("Copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                    }
                    if !isSaved {
                        Button {
                            context.insert(item)
                            try? context.save()
                            isSaved = true
                        } label: { Label("Save to History", systemImage: "bookmark").frame(maxWidth: .infinity).padding() }
                            .buttonStyle(.borderedProminent)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Button { showAIChoices = true } label: { Label(isAnalyzing ? "Analyzing…" : "Ask AI", systemImage: "sparkles").frame(maxWidth: .infinity).padding() }
                            .buttonStyle(.bordered).disabled(isAnalyzing || aiProvider == "Disabled" || URL(string: aiEndpoint)?.scheme != "https")
                        if aiProvider == "Disabled" || URL(string: aiEndpoint)?.scheme != "https" {
                            Text("Set an HTTPS server endpoint in Settings to enable AI analysis.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.padding(20)
            }.background(ScannerPalette.surface).navigationTitle("Scan detail").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { try? context.save(); dismiss() } } }
                .confirmationDialog("Send scanned text to your configured AI server?", isPresented: $showAIChoices, titleVisibility: .visible) {
                    Button("Summarize") { Task { await analyze("Summarize this document. Reply in the same language as the text.") } }
                    Button("Explain") { Task { await analyze("Explain the key ideas in this document. Reply in the same language as the text.") } }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("Only extracted text is sent. The image stays on this device.") }
                .alert("AI Result", isPresented: $showAIResult) { Button("Done", role: .cancel) {} } message: { Text(aiMessage) }
        }
    }

    @MainActor private func analyze(_ prompt: String) async {
        guard let endpoint = URL(string: aiEndpoint), endpoint.scheme == "https" else {
            aiMessage = "Enter a valid HTTPS server endpoint in Settings."
            showAIResult = true
            return
        }
        isAnalyzing = true
        defer { isAnalyzing = false }
        do { aiMessage = try await ProxyAIProvider(endpoint: endpoint, model: aiModel).respond(to: prompt, about: item.content) }
        catch { aiMessage = "AI analysis is currently unavailable. Your scan remains saved locally. (\(error.localizedDescription))" }
        showAIResult = true
    }
}

struct SettingsView: View {
    @AppStorage("appLanguage") private var appLanguage = "System"
    @AppStorage("appearance") private var appearance = "System"
    @AppStorage("autoScan") private var autoScan = true
    @AppStorage("haptics") private var haptics = true
    @AppStorage("saveAutomatically") private var saveAutomatically = true
    @AppStorage("recognitionLanguage") private var recognitionLanguage = "Automatic"
    @AppStorage("aiProvider") private var aiProvider = "Server Proxy"
    @AppStorage("aiEndpoint") private var aiEndpoint = ""
    @AppStorage("aiModel") private var aiModel = ""
    @Environment(\.modelContext) private var context
    @Query(sort: \ScanItem.createdAt, order: .reverse) private var scans: [ScanItem]
    @State private var confirmClear = false
    @State private var showPrivacy = false
    @State private var showTerms = false
    var body: some View {
        Form {
            Section("Appearance") {
                Picker("App Language", selection: $appLanguage) {
                    Text("System").tag("System")
                    Text("English").tag("en")
                    Text("Bahasa Indonesia").tag("id")
                }
                Picker("Color scheme", selection: $appearance) {
                    Text("System").tag("System")
                    Text("Light").tag("Light")
                    Text("Dark").tag("Dark")
                }
            }
            Section("Scanner") { Toggle("Auto Scan", isOn: $autoScan); Toggle("Haptic Feedback", isOn: $haptics); Toggle("Save Scan Automatically", isOn: $saveAutomatically) }
            Section("OCR") {
                Picker("Recognition language", selection: $recognitionLanguage) {
                    Text("Automatic (Indonesian + English)").tag("Automatic")
                    Text("Indonesian").tag("id-ID")
                    Text("English").tag("en-US")
                }
                Text("Vision uses the languages available on this iPhone. If an Indonesian OCR model is unavailable, the app falls back to Latin character recognition without Indonesian language correction.").font(.caption).foregroundStyle(.secondary)
            }
            Section("AI") {
                Picker("Provider", selection: $aiProvider) { Text("Server Proxy").tag("Server Proxy"); Text("Disabled").tag("Disabled") }
                if aiProvider == "Server Proxy" {
                    TextField("Model name", text: $aiModel).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("HTTPS server endpoint", text: $aiEndpoint).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("The endpoint receives scanned text only when you request AI analysis. Keep provider credentials on your server.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Storage") {
                LabeledContent("Saved scans", value: "\(scans.count)")
                ShareLink(item: exportData) { Label("Export Data", systemImage: "square.and.arrow.up") }
                Button("Clear History", role: .destructive) { confirmClear = true }.disabled(scans.isEmpty)
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                Button("Privacy Policy") { showPrivacy = true }
                Button("Terms") { showTerms = true }
            }
        }.navigationTitle("Settings")
            .confirmationDialog("Delete all saved scans?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Delete All Scans", role: .destructive) { Array(scans).forEach(context.delete); try? context.save() }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showPrivacy) { NavigationStack { List { Text("Scans are processed on this device and saved locally. Photos are not uploaded automatically. If you configure an AI server and request analysis, the selected scan text is sent to that server.") }.navigationTitle("Privacy").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showPrivacy = false } } } } }
            .sheet(isPresented: $showTerms) { NavigationStack { List { Text("Use AI Camera Scanner to capture and organize scans on your device. You are responsible for the content you scan and any server endpoint you configure. AI features send extracted text to that endpoint only after you choose an analysis action. The app does not include a hosted AI service.") }.navigationTitle("Terms").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showTerms = false } } } } }
    }

    private var exportData: String {
        let rows: [[String: String]] = scans.map { item in
            var row = [
                "id": item.id.uuidString,
                "type": item.type.rawValue,
                "title": item.title,
                "content": item.content,
                "createdAt": ISO8601DateFormatter().string(from: item.createdAt),
                "metadata": item.metadata
            ]
            if let confidence = item.confidence { row["confidence"] = String(confidence) }
            if let thumbnail = item.thumbnailData { row["thumbnailBase64"] = thumbnail.base64EncodedString() }
            return row
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }
}

struct CameraScreen: View {
    var onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showCamera = true
    @State private var capturedImage: UIImage?
    @AppStorage("autoScan") private var autoScan = true
    var body: some View {
        NavigationStack {
            Group {
              if let capturedImage {
                VStack(spacing: 18) {
                    Image(uiImage: capturedImage).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 18))
                    Text("Review your capture").font(.headline)
                    Button { onCapture(capturedImage); dismiss() } label: { Label("Analyze Scan", systemImage: "text.viewfinder").frame(maxWidth: .infinity).padding() }.buttonStyle(.borderedProminent)
                    Button("Retake") { self.capturedImage = nil; showCamera = true }
                }.padding()
              } else { VStack(spacing: 20) {
                Image(systemName: "camera.viewfinder").font(.system(size: 58)).foregroundStyle(ScannerPalette.accent)
                Text("Scan with camera").font(.title2.bold())
                Text("Use the camera to capture a page, text, or code. Your image is analyzed on this device.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button { showCamera = true } label: { Label("Take photo", systemImage: "camera.fill").frame(maxWidth: .infinity).padding() }.buttonStyle(.borderedProminent)
                if VNDocumentCameraViewController.isSupported {
                    DocumentScannerButton { image in handleCapture(image) }
                    .frame(maxWidth: .infinity).padding()
                }
                PhotosPickerInline { image in handleCapture(image) }
              }.padding(24) }
            }
            .navigationTitle("Scanner").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } } }
                .sheet(isPresented: $showCamera) { CameraImagePicker { image in handleCapture(image) } }
        }
    }
    private func handleCapture(_ image: UIImage) {
        if autoScan { onCapture(image); dismiss() }
        else { capturedImage = image; showCamera = false }
    }
}

private struct PhotosPickerInline: View {
    @State private var item: PhotosPickerItem?
    let onImage: (UIImage) -> Void
    var body: some View { PhotosPicker(selection: $item, matching: .images) { Label("Choose from Photos", systemImage: "photo").frame(maxWidth: .infinity) }.onChange(of: item) { _, value in Task { if let data = try? await value?.loadTransferable(type: Data.self), let image = UIImage(data: data) { onImage(image) } } } }
}

private struct CameraImagePicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary; picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        init(onImage: @escaping (UIImage) -> Void) { self.onImage = onImage }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { if let image = info[.originalImage] as? UIImage { onImage(image) }; picker.dismiss(animated: true) }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) }
    }
}

private struct DocumentScannerButton: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    func makeUIViewController(context: Context) -> ScannerLauncher { ScannerLauncher(onImage: onImage) }
    func updateUIViewController(_ controller: ScannerLauncher, context: Context) {}
    final class ScannerLauncher: UIViewController, VNDocumentCameraViewControllerDelegate {
        let onImage: (UIImage) -> Void
        init(onImage: @escaping (UIImage) -> Void) { self.onImage = onImage; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); guard presentedViewController == nil else { return }; let scanner = VNDocumentCameraViewController(); scanner.delegate = self; present(scanner, animated: true) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) { if scan.pageCount > 0 { onImage(scan.imageOfPage(at: 0)) }; controller.dismiss(animated: true) }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { controller.dismiss(animated: true) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { controller.dismiss(animated: true) }
    }
}
