import ByteCacheCore
import PhotosUI
import SwiftUI
#if os(iOS)
import AVFoundation
#endif
import UniformTypeIdentifiers
import Vision
#if canImport(VisionKit) && os(iOS)
import VisionKit
#endif

/// "Scan Code" (CP-84). On iPhone and iPad, Scan opens the camera straight away, with a button for
/// the photo library next to the shutter; "Choose Photo" (long-press Scan) opens the library. Camera
/// access is asked for by the system the first time; if it's off, an alert offers Settings or a photo.
/// On Mac, Scan picks an image file, or offers to paste an image when one is copied.
/// Recognised text and the picture are handed to `onScan`, usually to open the capture sheet.
struct ScanCodeFlow: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var choosingPhoto: Bool
    let onScan: (String, Data) -> Void

    @State private var model = ScanCodeModel()
    @State private var pickingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var usingCamera = false
    @State private var cameraOff = false
    @State private var importingFile = false
    @State private var choosingMacSource = false
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) {
                guard isPresented else { return }
                isPresented = false
                start()
            }
            .onChange(of: choosingPhoto) {
                guard choosingPhoto else { return }
                choosingPhoto = false
                #if os(iOS)
                pickingPhoto = true
                #else
                importingFile = true
                #endif
            }
            #if os(iOS)
            .alert("Camera Access Is Off", isPresented: $cameraOff) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                Button("Choose Photo") { pickingPhoto = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("To scan code with the camera, turn on Camera for ByteCache in Settings. You can also choose a photo of the code.")
            }
            #else
            .confirmationDialog("Scan Code", isPresented: $choosingMacSource) {
                Button("Capture Screen Area…") { Task { await captureScreen() } }
                Button("Choose Image…") { importingFile = true }
                if Self.pastedImage() != nil {
                    Button("Paste Image") { if let data = Self.pastedImage() { run(data) } }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Capture code from a video, PDF or shared screen, or read an image.")
            }
            #endif
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

    /// Scan was tapped.
    private func start() {
        #if os(iOS)
        if Self.previewCamera { usingCamera = true; return }
        // No camera here (simulator, or a device VisionKit can't scan on): the photo library instead.
        guard DataScannerViewController.isSupported else { pickingPhoto = true; return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            usingCamera = true
        case .notDetermined:
            // The system asks, in context, the first time the camera is needed.
            Task {
                if await AVCaptureDevice.requestAccess(for: .video) { usingCamera = true } else { cameraOff = true }
            }
        default:
            cameraOff = true
        }
        #else
        choosingMacSource = true
        #endif
    }

    private func run(_ data: Data) {
        Task {
            if let text = await model.recognize(imageData: data) { onScan(text, data) }
        }
    }

    #if os(macOS)
    /// macOS's own screenshot tool: the person drags over the code, it goes to the clipboard, and
    /// ByteCache reads it from there. Cancelling (Esc) leaves the clipboard alone and does nothing.
    private func captureScreen() async {
        let board = NSPasteboard.general
        let before = board.changeCount
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-c", "-x"]
        do {
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, any Error>) in
                process.terminationHandler = { _ in done.resume() }
                do { try process.run() } catch { done.resume(throwing: error) }
            }
        } catch {
            AppLog.shared.record("scan", "screen capture couldn't start: \(type(of: error))")
            model.error = "Screen capture couldn't start. Press ⌃⇧⌘4 to copy part of the screen, then choose Scan → Paste Image."
            return
        }
        guard board.changeCount != before, let data = Self.pastedImage() else { return }
        run(data)
    }
    #endif

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
    /// Long-press (iPhone/iPad) on the Scan button: "Scan with Camera" or "Choose Photo" (CP-84).
    /// The Mac has no camera, and right-click there customises the toolbar, so nothing is added.
    @ViewBuilder
    public func scanButtonMenu(camera: @escaping () -> Void, photo: @escaping () -> Void) -> some View {
        #if os(iOS)
        contextMenu {
            Button(action: camera) { Label("Scan with Camera", symbol: .scan) }
            Button(action: photo) { Label("Choose Photo", symbol: .image) }
        }
        #else
        self
        #endif
    }

    /// `isPresented`: Scan was tapped (camera on iPhone/iPad). `choosingPhoto`: "Choose Photo".
    public func scanCodeFlow(isPresented: Binding<Bool>, choosingPhoto: Binding<Bool> = .constant(false),
                             onScan: @escaping (_ text: String, _ image: Data) -> Void) -> some View {
        modifier(ScanCodeFlow(isPresented: isPresented, choosingPhoto: choosingPhoto, onScan: onScan))
    }
}

#if os(iOS)
/// Live camera with text highlighting (VisionKit) and a camera-style shutter at the bottom, where the
/// thumb is. The shutter takes a still for layout-aware recognition.
struct CameraScanner: View {
    let onFinish: (Data?) -> Void
    @State private var handle = ScannerHandle()
    @State private var capturing = false
    @State private var photo: PhotosPickerItem?
    /// The on-device / check-brackets hint shows until dismissed or the first capture (CP-84);
    /// Settings → Show Scan Tip brings it back.
    @AppStorage(ScanTip.seenKey) private var tipSeen = false
    /// A photo taken through a smudged lens, waiting for Retake or Use Photo.
    @State private var smudgedPhoto: Data?

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
                if !tipSeen { tip.padding(.top, 10) }
                Spacer()
                HStack {
                    libraryButton.frame(maxWidth: .infinity)
                    shutter
                    // Balances the library button so the shutter stays centred.
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
                .padding(.top, 18)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.45))
            }
            // Partially folded (iPhone Duo), the controls take one half so the shutter isn't on the hinge.
            .centeredAwayFromFold()
        }
        .preferredColorScheme(.dark)
        .onAppear { Haptics.prepare() }
        .alert("Lens Looks Smudged", isPresented: Binding(get: { smudgedPhoto != nil }, set: { if !$0 { smudgedPhoto = nil } })) {
            Button("Retake", role: .cancel) { smudgedPhoto = nil }
            Button("Use Photo") {
                let data = smudgedPhoto
                smudgedPhoto = nil
                onFinish(data)
            }
        } message: {
            Text("A smudge on the camera lens blurs small characters. Wipe the lens and take the picture again.")
        }
    }

    private var tip: some View {
        HStack(alignment: .top, spacing: 10) {
            Icon(.infoCircle)
            Text(ScanTip.text).font(.footnote).fixedSize(horizontal: false, vertical: true)
            Button { tipSeen = true } label: { Icon(.close) }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide Tip")
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
    }

    /// The photo library, next to the shutter as in the Camera app (CP-84).
    private var libraryButton: some View {
        PhotosPicker(selection: $photo, matching: .images) {
            Icon(.image)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityLabel("Choose Photo")
        .onChange(of: photo) {
            guard let photo else { return }
            Task {
                let data = try? await photo.loadTransferable(type: Data.self)
                self.photo = nil
                if let data { onFinish(data) }
            }
        }
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
        Haptics.play(.tap)
        capturing = true
        tipSeen = true
        Task { @MainActor in
            let image = try? await scanner.capturePhoto()
            let data = image?.jpegData(compressionQuality: 0.95)
            if let cgImage = image?.cgImage, await LensCheck.isSmudged(cgImage) {
                capturing = false
                Haptics.play(.error)
                smudgedPhoto = data
                return
            }
            capturing = false
            onFinish(data)
        }
    }
}

/// Vision's lens smudge check (iOS 26), so a blurry scan isn't blamed on the code.
enum LensCheck {
    /// Only a confident result counts, so a clean lens never nags.
    static let threshold: Float = 0.9

    static func isSmudged(_ image: CGImage) async -> Bool {
        guard #available(iOS 26.0, *) else { return false }
        guard let observation = try? await DetectLensSmudgeRequest().perform(on: image) else { return false }
        return observation.confidence >= threshold
    }
}

/// The scanner's one-time hint (CP-84).
enum ScanTip {
    static let seenKey = "scanTipSeen"
    static let text = "ByteCache reads the code on this device. Check it before saving: a lone closing bracket on its own line can be missed."
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
