import ByteCatchCore
import ByteCatchLanguage
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Backup & Import.
@MainActor @Observable
final class BackupModel {
    var working: String?
    var message: String?
    var exportFile: ExportFile?
    var candidates: [ImportCandidate]?
    let session: SessionManager
    private let detector = LanguageDetector()

    init(session: SessionManager) {
        self.session = session
    }

    private var stamp: String { Date().formatted(.iso8601.year().month().day()) }

    func prepareZip() async {
        await run("Collecting snippets…") { client in
            let all = try await SnippetFetcher.all(client)
            let zip = try SnippetBackup.zip(folder: SnippetBackup.folder(for: all), named: "ByteCatch Snippets \(self.stamp)")
            let file = FileWrapper(regularFileWithContents: try Data(contentsOf: zip))
            file.preferredFilename = zip.lastPathComponent
            self.exportFile = ExportFile(wrapper: file, contentType: .zip)
        }
    }

    func prepareJSON() async {
        await run("Collecting snippets…") { client in
            let all = try await SnippetFetcher.all(client)
            let data = try SnippetBackup(snippets: all, server: client.server.base.absoluteString).encoded()
            let file = FileWrapper(regularFileWithContents: data)
            file.preferredFilename = "ByteCatch Backup \(self.stamp).json"
            self.exportFile = ExportFile(wrapper: file, contentType: .json)
        }
    }

    func importBackup(from url: URL) async {
        await run("Importing…") { _ in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let backup = try SnippetBackup.decode(try Data(contentsOf: url))
            let result = try await BackupImporter(session: self.session).importBackup(backup)
            self.message = "Imported \(result.created), skipped \(result.skipped) already here"
                + (result.failed > 0 ? ", \(result.failed) failed." : ".")
        }
    }

    func importGist(_ link: String) async {
        await run("Fetching gist…") { _ in
            do { self.candidates = try await GistImport.fetch(link, detector: self.detector) }
            catch let error as ImportError { self.message = error.message }
        }
    }

    func importFiles(_ urls: [URL], vscode: Bool) async {
        await run("Reading files…") { _ in
            var found: [ImportCandidate] = []
            for url in urls {
                if vscode {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    do { found += try VSCodeSnippetImport.parse(try Data(contentsOf: url), fileName: url.lastPathComponent, detector: self.detector) }
                    catch let error as ImportError { self.message = error.message }
                } else {
                    found += FileImport.candidates(from: [url], detector: self.detector)
                }
            }
            if found.isEmpty, self.message == nil { self.message = "No text files found to import." }
            else if !found.isEmpty { self.candidates = found }
        }
    }

    private func run(_ status: String, _ work: @escaping (APIClient) async throws -> Void) async {
        guard let client = session.client else {
            message = "Sign in first."
            return
        }
        working = status
        defer { working = nil }
        do {
            try await work(client)
        } catch is SnippetBackup.InvalidBackup {
            message = "That file isn't a ByteCatch backup."
        } catch let error as APIError {
            message = ErrorText.message(for: error)
        } catch {
            message = "Something went wrong: \(error.localizedDescription)"
        }
    }
}

struct BackupView: View {
    @State var model: BackupModel
    @State private var exporting = false
    @State private var importing = false
    @State private var importMode = ImportMode.backup
    @State private var askingGist = false
    @State private var gistLink = ""

    private enum ImportMode { case backup, vscode, files }

    private var importTypes: [UTType] {
        switch importMode {
        case .backup: [.json]
        case .vscode: [.json, UTType(filenameExtension: "code-snippets") ?? .json]
        case .files: [.item, .folder]
        }
    }

    var body: some View {
        List {
            Section {
                Button { Task { await model.prepareZip(); exporting = model.exportFile != nil } } label: {
                    SettingsLabel(title: "Export as ZIP…", symbol: .download, color: .blue)
                }
                Button { Task { await model.prepareJSON(); exporting = model.exportFile != nil } } label: {
                    SettingsLabel(title: "Export JSON Backup…", symbol: .document, color: .gray)
                }
            } header: {
                Text("Export")
            } footer: {
                Text("ZIP: every snippet as files, named like Save. JSON: a full backup ByteCatch can import again, including categories, pins and favourites.")
            }

            Section {
                Button { importMode = .backup; importing = true } label: {
                    SettingsLabel(title: "Import Backup…", symbol: .restore, color: .green)
                }
            } header: {
                Text("Restore")
            } footer: {
                Text("Snippets you already have (same title and code) are skipped.")
            }

            Section {
                Button { askingGist = true } label: {
                    SettingsLabel(title: "GitHub Gist Link…", symbol: .link, color: .black)
                }
                Button { importMode = .vscode; importing = true } label: {
                    SettingsLabel(title: "VS Code Snippets File…", symbol: .code, color: .blue)
                }
                Button { importMode = .files; importing = true } label: {
                    SettingsLabel(title: "Files or a Folder…", symbol: .document, color: .orange)
                }
            } header: {
                Text("Import From")
            } footer: {
                Text("You'll see what will be imported before anything is created. Languages are detected automatically.")
            }
        }
        .foregroundStyle(.primary)
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Backup & Import")
        .disabled(model.working != nil)
        .overlay {
            if let working = model.working {
                ProgressView(working).padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .fileExporter(isPresented: $exporting,
                      document: SnippetFileDocument(wrapper: model.exportFile?.wrapper ?? FileWrapper(regularFileWithContents: Data())),
                      contentType: model.exportFile?.contentType ?? .data,
                      defaultFilename: model.exportFile?.filename) { result in
            if case .success = result { model.message = "Saved." }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: importTypes,
                      allowsMultipleSelection: importMode != .backup) { result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            Task {
                switch importMode {
                case .backup: await model.importBackup(from: urls[0])
                case .vscode: await model.importFiles(urls, vscode: true)
                case .files: await model.importFiles(urls, vscode: false)
                }
            }
        }
        .alert("Import Gist", isPresented: $askingGist) {
            TextField("https://gist.github.com/…", text: $gistLink)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { gistLink = "" }
            Button("Fetch") {
                let link = gistLink
                gistLink = ""
                Task { await model.importGist(link) }
            }
        } message: {
            Text("Paste a public or secret gist link.")
        }
        .sheet(isPresented: Binding(get: { model.candidates != nil }, set: { if !$0 { model.candidates = nil } })) {
            NavigationStack {
                ImportPreviewView(candidates: model.candidates ?? [], session: model.session) { message in
                    model.candidates = nil
                    if !message.isEmpty { model.message = message }
                }
            }
        }
        .alert("Backup", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.message ?? "")
        }
    }
}
