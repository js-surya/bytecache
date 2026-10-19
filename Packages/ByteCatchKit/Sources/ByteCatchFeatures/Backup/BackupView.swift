import ByteCatchCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Backup & Import.
@MainActor @Observable
final class BackupModel {
    var working: String?
    var message: String?
    var exportFile: ExportFile?
    let session: SessionManager

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
                Button { importing = true } label: {
                    SettingsLabel(title: "Import Backup…", symbol: .restore, color: .green)
                }
            } header: {
                Text("Import")
            } footer: {
                Text("Snippets you already have (same title and code) are skipped.")
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
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { Task { await model.importBackup(from: url) } }
        }
        .alert("Backup", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.message ?? "")
        }
    }
}
