import CreateML
import Foundation
import NaturalLanguage
import ByteCacheLanguage

// Usage: swift run --package-path Tools/LanguageModelTrainer train
setvbuf(stdout, nil, _IOLBF, 0)

// Reads .data/ (from fetch-sources.sh) and sources.lock.json; writes the model, held-out fixture and DATA.md.

let toolDir = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let repoRoot = toolDir.deletingLastPathComponent().deletingLastPathComponent()
let languageDir = repoRoot.appending(path: "Packages/ByteCacheKit/Sources/ByteCacheLanguage")
let modelURL = languageDir.appending(path: "Resources/ByteCacheLanguage.mlmodel")
let heldoutURL = repoRoot.appending(path: "Packages/ByteCacheKit/Tests/ByteCacheLanguageTests/Fixtures/heldout.jsonl")
let dataMdURL = languageDir.appending(path: "DATA.md")

let labels = Set(LanguageCatalog.ids).subtracting(ruleOnlyIds)
let bands: [(name: String, range: ClosedRange<Int>, trainCap: Int, heldoutCap: Int)] = [
    ("short", 1...4, 1_500, 60),
    ("medium", 5...30, 1_500, 40),
    ("long", 31...200, 1_000, 15),
]
let skippedDirs: Set<String> = [".git", "node_modules", "vendor", "dist", "build", "third_party", "external", "deps", ".github"]
let maxFileBytes = 300_000

// MARK: Deterministic randomness (seed 42)

struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
var rng = SplitMix64(state: 42)

func stableHash(_ s: String) -> UInt64 {
    s.utf8.reduce(1_469_598_103_934_665_603) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 } // FNV-1a
}

// MARK: Collect files

struct SourceFile { let path: String; let label: String }

func label(for file: URL, allowed: Set<String>) -> String? {
    let ext = file.pathExtension
    guard !ext.isEmpty, var id = LanguageCatalog.id(forExtension: ext) else { return nil }
    if id == "c", !allowed.contains("c"), allowed.contains("cpp") { id = "cpp" } // headers in C++ repos
    return allowed.contains(id) && labels.contains(id) ? id : nil
}

func walk(_ root: URL, _ body: (URL) -> Void) {
    guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]) else { return }
    for case let url as URL in e {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        if values?.isDirectory == true {
            if skippedDirs.contains(url.lastPathComponent) { e.skipDescendants() }
            continue
        }
        if (values?.fileSize ?? 0) > maxFileBytes || url.lastPathComponent.contains(".min.") { continue }
        body(url)
    }
}

struct LockEntry: Decodable { let repo: String; let license: String; let commit: String; let languages: [String]? }
let lock = try JSONDecoder().decode([LockEntry].self, from: Data(contentsOf: toolDir.appending(path: "sources.lock.json")))

var files: [SourceFile] = []
for entry in lock where entry.languages != nil {
    let dir = toolDir.appending(path: ".data/repos/\(entry.repo.replacingOccurrences(of: "/", with: "__"))")
    let allowed = Set(entry.languages!).union(["markdown", "yaml"])
    walk(dir) { url in
        if let id = label(for: url, allowed: allowed) { files.append(SourceFile(path: url.path, label: id)) }
    }
}
for (folder, id) in linguistMapping where labels.contains(id) {
    walk(toolDir.appending(path: ".data/linguist/samples/\(folder)")) { url in
        files.append(SourceFile(path: url.path, label: id))
    }
}
print("files:", files.count)

// MARK: Chunk

struct Chunk: Codable { let id: String; let band: String; let lines: Int; let text: String }

func readLines(_ path: String) -> [Substring]? {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    if lines.contains(where: { $0.count > 1_000 }) { return nil } // minified or generated
    return lines
}

@MainActor func chunks(of lines: [Substring], band: ClosedRange<Int>, count: Int) -> [String] {
    var result: [String] = []
    for _ in 0..<(count * 3) where result.count < count {
        let length = Int.random(in: band, using: &rng)
        guard lines.count >= length else { break }
        let start = Int.random(in: 0...(lines.count - length), using: &rng)
        let text = lines[start..<(start + length)].joined(separator: "\n")
        let meaningful = CodeTokenizer.tokens(text).filter { $0 != "NL" && $0.first?.isLetter == true }
        if meaningful.count >= 3 { result.append(text) }
    }
    return result
}

var train: [String: [String]] = [:]
var heldout: [Chunk] = []
var perLabelFiles: [String: Int] = [:]

for (id, group) in Dictionary(grouping: files, by: \.label).sorted(by: { $0.key < $1.key }) {
    let shuffled = group.shuffled(using: &rng)
    perLabelFiles[id] = group.count
    let testFiles = shuffled.filter { stableHash($0.path) % 100 < 15 }
    let trainFiles = shuffled.filter { stableHash($0.path) % 100 >= 15 }
    for band in bands {
        func fill(_ pool: [SourceFile], cap: Int) -> [String] {
            var out: [String] = []
            let perFile = max(1, cap / max(pool.count, 1) + 1)
            for file in pool where out.count < cap {
                guard let lines = readLines(file.path) else { continue }
                out += chunks(of: lines, band: band.range, count: min(perFile, cap - out.count))
            }
            return out
        }
        train[id, default: []] += fill(trainFiles, cap: band.trainCap).map { CodeTokenizer.features($0) }
        heldout += fill(testFiles, cap: band.heldoutCap).map {
            Chunk(id: id, band: band.name, lines: $0.split(separator: "\n", omittingEmptySubsequences: false).count, text: $0)
        }
    }
    print(id, "files", group.count, "train", train[id]!.count)
}

// MARK: Vocabulary cap
// Model size grows with distinct words. Keep the words found in the most training samples;
// at inference, words the model never saw are simply ignored, so the app needs no word list.

let maxVocabulary = 24_000
var documentFrequency: [Substring: Int] = [:]
for docs in train.values {
    for doc in docs {
        for word in Set(doc.split(separator: " ")) { documentFrequency[word, default: 0] += 1 }
    }
}
let vocabulary = Set(documentFrequency.sorted { $0.value > $1.value }.prefix(maxVocabulary).map(\.key))
print("vocabulary:", documentFrequency.count, "→", vocabulary.count)
for (label, docs) in train {
    train[label] = docs.map { $0.split(separator: " ").filter { vocabulary.contains($0) }.joined(separator: " ") }
}

// MARK: Train

let parameters = MLTextClassifier.ModelParameters(validation: .none, algorithm: .maxEnt(revision: 1), language: .english)
let start = Date()
let classifier = try MLTextClassifier(trainingData: train, parameters: parameters)
print("trained in", Int(Date().timeIntervalSince(start)), "s")

// MARK: Evaluate (classifier alone; the app adds rule stages on top)

let nl = try NLModel(mlModel: classifier.model)
var stats: [String: (n: Int, top1: Int, top3: Int)] = [:]
var misses: [String: Int] = [:]
for chunk in heldout {
    let ranked = nl.predictedLabelHypotheses(for: CodeTokenizer.features(chunk.text), maximumCount: 3)
        .sorted { $0.value > $1.value }.map(\.key)
    var s = stats[chunk.band] ?? (0, 0, 0)
    s.n += 1
    if ranked.first == chunk.id { s.top1 += 1 } else { misses["\(chunk.id)→\(ranked.first ?? "-")", default: 0] += 1 }
    if ranked.contains(chunk.id) { s.top3 += 1 }
    stats[chunk.band] = s
}
for band in bands.map(\.name) {
    let s = stats[band]!
    print(String(format: "%@: n=%d top1=%.3f top3=%.3f", band, s.n, Double(s.top1) / Double(s.n), Double(s.top3) / Double(s.n)))
}
print("top confusions:", misses.sorted { $0.value > $1.value }.prefix(15).map { "\($0.key) \($0.value)" }.joined(separator: ", "))

// MARK: Write outputs

try FileManager.default.createDirectory(at: heldoutURL.deletingLastPathComponent(), withIntermediateDirectories: true)
let encoder = JSONEncoder()
encoder.outputFormatting = .sortedKeys
try heldout.map { String(decoding: try encoder.encode($0), as: UTF8.self) }.joined(separator: "\n")
    .write(to: heldoutURL, atomically: true, encoding: .utf8)

try classifier.write(to: modelURL, metadata: MLModelMetadata(
    author: "ByteCache", shortDescription: "Code language classifier over CodeTokenizer.features", version: "1"
))
let size = (try FileManager.default.attributesOfItem(atPath: modelURL.path)[.size] as? Int) ?? 0
print("model bytes:", size)

var md = """
# Language model training data

Generated by `Tools/LanguageModelTrainer` (`fetch-sources.sh`, then `swift run --package-path Tools/LanguageModelTrainer train`).
Only permissively licensed sources. Code is used to train a statistical model; no source text ships in the app.
The held-out test fixture contains short excerpts from these sources for evaluation only.

| Source | License | Commit |
|---|---|---|

"""
for entry in lock {
    md += "| \(entry.repo) | \(entry.license) | `\(entry.commit.prefix(12))` |\n"
}
md += "\nFiles per language: " + perLabelFiles.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ") + "\n"
try md.write(to: dataMdURL, atomically: true, encoding: .utf8)
print("done")
