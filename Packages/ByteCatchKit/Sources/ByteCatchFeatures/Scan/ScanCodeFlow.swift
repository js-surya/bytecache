import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
#if canImport(VisionKit) && os(iOS)
import VisionKit
#endif

/// "Scan Code": camera (iPhone/iPad), photo library, or an image file / pasted image (Mac).
/// Recognised text is handed to `onText`, usually to open the capture sheet.
struct ScanCodeFlow: ViewModifier {
    @Binding var isPresented: Bool
    let onText: (String) -> Void

    @State private var model = ScanCodeModel()
    @State private var pickingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var usingCamera = false
    @State private var importingFile = false

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Scan Code", isPresented: $isPresented, titleVisibility: .visible) {
                #if os(iOS)
                if CameraScanner.isAvailable {
                    Button("Camera") { usingCamera = true }
                }
                Button("Choose Photo") { pickingPhoto = true }
                #else
                Button("Choose Image…") { importingFile = true }
                if Self.pastedImage() != nil {
                    Button("Paste Image") { if let data = Self.pastedImage() { run(data) } }
                }
                #endif
            } message: {
                Text("ByteCatch reads the code on this device. Check it before saving — a lone closing bracket on its own line can be missed.")
            }
            .photosPicker(isPresented: $pickingPhoto, selection: $photo, matching: .images)
            .onChange(of: photo) {
                guard let photo else { return }
                Task {
                    if let data = try? await photo.loadTransferable(type: Data.self) { run(data) }
                    self.photo = nil
                }
            }
            .fileImporter(isPresented: $importingFile, allowedContentTypes: [.image]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) { run(data) }
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $usingCamera) {
                CameraScanner { data in
                    usingCamera = false
                    if let data { run(data) }
                }
                .ignoresSafeArea()
            }
            #endif
            .overlay {
                if model.isRecognizing {
                    ProgressView("Reading code…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .alert("Couldn't Read Code", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.error ?? "")
            }
    }

    private func run(_ data: Data) {
        Task {
            if let text = await model.recognize(imageData: data) { onText(text) }
        }
    }

    #if os(macOS)
    static func pastedImage() -> Data? {
        let board = NSPasteboard.general
        if let png = board.data(forType: .png) { return png }
        if let tiff = board.data(forType: .tiff) { return tiff }
        return nil
    }
    #endif
}

extension View {
    public func scanCodeFlow(isPresented: Binding<Bool>, onText: @escaping (String) -> Void) -> some View {
        modifier(ScanCodeFlow(isPresented: isPresented, onText: onText))
    }
}

#if os(iOS)
/// Live camera with text highlighting (VisionKit). Capture takes a still for layout-aware recognition.
struct CameraScanner: UIViewControllerRepresentable {
    let onFinish: (Data?) -> Void

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.text()], qualityLevel: .accurate,
                                                isHighlightingEnabled: true)
        scanner.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { _ in onFinish(nil) })
        scanner.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Capture", primaryAction: UIAction { [weak scanner] _ in
            Task { @MainActor in
                let image = try? await scanner?.capturePhoto()
                onFinish(image?.jpegData(compressionQuality: 0.95))
            }
        })
        scanner.navigationItem.title = "Point at code"
        try? scanner.startScanning()
        return UINavigationController(rootViewController: scanner)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}
#endif
