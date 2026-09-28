import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ScanItem.createdAt, order: .reverse) private var scans: [ScanItem]
    @State private var selection = 0
    @State private var showCamera = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var busy = false
    @State private var alertMessage: String?
    @State private var detail: ScanItem?
    @State private var searchText = ""
    @AppStorage("appearance") private var appearance = "System"
    @AppStorage("appLanguage") private var appLanguage = "System"
    @AppStorage("haptics") private var haptics = true
    @AppStorage("saveAutomatically") private var saveAutomatically = true
    @AppStorage("recognitionLanguage") private var recognitionLanguage = "Automatic"

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { home }.tabItem { Label("Home", systemImage: "house") }.tag(0)
            NavigationStack { scanLanding }.tabItem { Label("Scan", systemImage: "viewfinder") }.tag(1)
            NavigationStack { history }.tabItem { Label("History", systemImage: "clock.arrow.circlepath") }.tag(2)
            NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "gearshape") }.tag(3)
        }
        .tint(ScannerPalette.accent)
        .preferredColorScheme(appearance == "System" ? nil : (appearance == "Dark" ? .dark : .light))
        .environment(\.locale, appLanguage == "System" ? Locale.current : Locale(identifier: appLanguage))
        .fullScreenCover(isPresented: $showCamera) { CameraScreen { image in Task { await process(image) } } }
        .onChange(of: selectedPhoto) { _, item in guard let item else { return }; Task { if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { await process(image) } } }
        .sheet(item: $detail) { item in ScanDetailView(item: item, isInitiallySaved: scans.contains(where: { $0.id == item.id })) }
        .alert("AI Camera Scanner", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(LocalizedStringKey(alertMessage ?? "")) }
        .overlay { if busy { ProgressView("Analyzing image…").padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)) } }
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("AI Scanner").font(.largeTitle.bold())
                    Text("Scan anything. Understand everything.").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.top, 12)
                Button { showCamera = true } label: {
                    VStack(spacing: 14) {
                        Image(systemName: "viewfinder").font(.system(size: 36, weight: .medium))
                        Text("Start scanning").font(.headline)
                    }.foregroundStyle(ScannerPalette.onAccent).frame(maxWidth: .infinity).frame(height: 170)
                        .background(ScannerPalette.accent, in: RoundedRectangle(cornerRadius: 28))
                }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 14) {
                    Text("Quick actions").font(.title3.bold())
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        QuickAction(title: "Scan Document", icon: "doc.text.viewfinder") { showCamera = true }
                        QuickAction(title: "Scan Text", icon: "text.viewfinder") { showCamera = true }
                        QuickAction(title: "Scan QR", icon: "qrcode.viewfinder") { showCamera = true }
                        QuickAction(title: "Scan Barcode", icon: "barcode.viewfinder") { showCamera = true }
                        QuickAction(title: "Identify Object", icon: "sparkle.magnifyingglass") { showCamera = true }
                        PhotosPicker(selection: $selectedPhoto, matching: .images) { actionLabel(LocalizedStringKey("Import Photo"), icon: "photo") }
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Text("Recent scans").font(.title3.bold()); Spacer(); Button("See all") { selection = 2 }.font(.subheadline) }
                    if scans.isEmpty { ContentUnavailableView("No scans yet", systemImage: "doc.viewfinder", description: Text("Your saved scans will appear here.")) }
                    else { ForEach(scans.prefix(4)) { item in Button { detail = item } label: { ScanRow(item: item) }.buttonStyle(.plain) } }
                }
            }.padding(20)
        }.background(ScannerPalette.surface).toolbar(.hidden, for: .navigationBar)
    }

    private var scanLanding: some View {
        VStack(spacing: 18) {
            Image(systemName: "viewfinder").font(.system(size: 58)).foregroundStyle(ScannerPalette.accent)
            Text("Ready when you are").font(.title2.bold())
            Text("Capture text, codes, and documents privately on your device.").multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button { showCamera = true } label: { Label("Open camera", systemImage: "camera.fill").frame(maxWidth: .infinity).padding() }.buttonStyle(.borderedProminent)
            PhotosPicker(selection: $selectedPhoto, matching: .images) { Label("Choose a photo", systemImage: "photo") }.buttonStyle(.bordered)
        }.padding(30).navigationTitle("Scan")
    }

    private var history: some View {
        List {
            if scans.isEmpty { ContentUnavailableView("No scans yet", systemImage: "clock", description: Text("Scans you save will be listed here.")) }
            ForEach(filteredScans) { item in Button { detail = item } label: { ScanRow(item: item) }.swipeActions { Button("Delete", systemImage: "trash", role: .destructive) { context.delete(item) } } }
        }.navigationTitle("History").searchable(text: $searchText, prompt: "Search scans")
    }

    private var filteredScans: [ScanItem] {
        guard !searchText.isEmpty else { return scans }
        return scans.filter { $0.title.localizedCaseInsensitiveContains(searchText) || $0.content.localizedCaseInsensitiveContains(searchText) || $0.type.title.localizedCaseInsensitiveContains(searchText) }
    }

    private func process(_ image: UIImage) async {
        busy = true
        defer { busy = false }
        do {
            let code = try await ScanAnalysis.recognizeCode(in: image)
            let text = try await ScanAnalysis.recognizeText(in: image, language: recognitionLanguage)
            let type: ScanType = code == nil ? .text : ((code?.0.lowercased().contains("qr") == true) ? .qr : .barcode)
            let content = code.map { "\($0.0): \($0.1)" } ?? text
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { alertMessage = "Unable to recognize text. Try moving closer or improving lighting."; return }
            let title = String(content.components(separatedBy: .newlines).first?.prefix(48) ?? "New scan")
            let item = ScanItem(type: type, title: title, content: content, thumbnailData: image.jpegData(compressionQuality: 0.72))
            if saveAutomatically { context.insert(item); try context.save() }
            detail = item
            if haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        } catch { alertMessage = error.localizedDescription }
    }
}

private struct QuickAction: View {
    let title: String; let icon: String; let action: () -> Void
    var body: some View { Button(action: action) { actionLabel(LocalizedStringKey(title), icon: icon) }.buttonStyle(.plain) }
}
private func actionLabel(_ title: LocalizedStringKey, icon: String) -> some View {
    VStack(alignment: .leading, spacing: 14) { Image(systemName: icon).font(.title2).foregroundStyle(ScannerPalette.accent); Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color(uiColor: .label)) }
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading).padding(14).background(ScannerPalette.card, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(ScannerPalette.outline, lineWidth: 0.5))
}
enum ScannerPalette {
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 18/255, green: 19/255, blue: 23/255, alpha: 1) : UIColor(red: 248/255, green: 248/255, blue: 250/255, alpha: 1)
    })
    static let card = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 30/255, green: 31/255, blue: 35/255, alpha: 1) : .white
    })
    static let raised = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 41/255, green: 42/255, blue: 46/255, alpha: 1) : UIColor(red: 235/255, green: 236/255, blue: 239/255, alpha: 1)
    })
    static let accent = Color(red: 42/255, green: 229/255, blue: 0)
    static let onAccent = Color(red: 5/255, green: 57/255, blue: 0)
    static let outline = Color(red: 60/255, green: 75/255, blue: 53/255)
}
struct ScanRow: View {
    let item: ScanItem
    var body: some View { HStack(spacing: 14) {
        Image(systemName: item.type.symbol).font(.title3).foregroundStyle(ScannerPalette.accent).frame(width: 48, height: 48).background(ScannerPalette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title).font(.headline).lineLimit(1)
            HStack(spacing: 4) {
                Text(LocalizedStringKey(item.type.title))
                Text("·")
                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
            }.font(.caption).foregroundStyle(.secondary)
        }
        Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
    }.padding(.vertical, 4) }
}
