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
                if CameraScanner.isAvailable || Self.previewCamera {
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
            .onAppear { if Self.previewCamera { usingCamera = true } }
            .fullScreenCover(isPresented: $usingCamera) {
                CameraScanner { data in
                    usingCamera = false
                    if let data { run(data) }
                }
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

    /// Debug builds: `-BCScanPreview` shows the camera screen on the simulator (no camera there).
    static var previewCamera: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-BCScanPreview")
        #else
        false
        #endif
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
/// Live camera with text highlighting (VisionKit) and a camera-style shutter at the bottom, where the
/// thumb is. The shutter takes a still for layout-aware recognition.
struct CameraScanner: View {
    let onFinish: (Data?) -> Void
    @State private var handle = ScannerHandle()
    @State private var capturing = false

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        ZStack {
            if Self.isAvailable {
                ScannerView(handle: handle).ignoresSafeArea()
            } else {
                // Debug preview on the simulator, which has no camera.
                Color.black.ignoresSafeArea()
            }
            VStack(spacing: 0) {
                HStack {
                    Button("Cancel") { onFinish(nil) }
                        .buttonStyle(.bordered)
                    Spacer()
                    Text("Point at code").font(.headline).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.black.opacity(0.35), in: Capsule())
                    Spacer()
                    // Balances Cancel so the title stays centred.
                    Button("Cancel") {}.buttonStyle(.bordered).hidden()
                }
                .padding(.horizontal)
                .padding(.top, 8)
                Spacer()
                shutter
                    .padding(.top, 18)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(0.45))
            }
        }
        .preferredColorScheme(.dark)
    }

    private var shutter: some View {
        Button(action: capture) {
            ZStack {
                Circle().strokeBorder(.white, lineWidth: 5).frame(width: 78, height: 78)
                Circle().fill(.white).frame(width: 64, height: 64).scaleEffect(capturing ? 0.85 : 1)
                if capturing { ProgressView().tint(.black) }
            }
            .frame(width: 88, height: 88)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(capturing)
        .accessibilityLabel("Capture")
        .accessibilityHint("Takes a picture and reads the code in it.")
        .animation(.easeOut(duration: 0.15), value: capturing)
    }

    private func capture() {
        guard let scanner = handle.scanner else { return }
        capturing = true
        Task { @MainActor in
            let image = try? await scanner.capturePhoto()
            capturing = false
            onFinish(image?.jpegData(compressionQuality: 0.95))
        }
    }
}

@MainActor
final class ScannerHandle {
    weak var scanner: DataScannerViewController?
}

private struct ScannerView: UIViewControllerRepresentable {
    let handle: ScannerHandle

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.text()], qualityLevel: .accurate,
                                                isHighlightingEnabled: true)
        handle.scanner = scanner
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}
}
#endif
