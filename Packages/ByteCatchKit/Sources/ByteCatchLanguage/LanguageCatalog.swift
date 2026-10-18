import Foundation

/// ByteStash language identifiers. Detection results must always be one of these.
public enum LanguageCatalog {
    public static let ids: [String] = [
        "javascript", "typescript", "html", "css", "php", "webassembly", "c", "cpp", "csharp", "vba",
        "rust", "go", "java", "kotlin", "scala", "groovy", "python", "ruby", "perl", "lua",
        "bash", "powershell", "batch", "sql", "mongodb", "markdown", "yaml", "json", "xml", "toml",
        "ini", "conf", "vimscript", "terraform", "dockerfile", "kubernetes", "swift", "r", "julia", "dart",
        "elm", "apex", "solidity", "vyper", "verilog", "systemverilog", "latex", "matlab", "graphql", "cypher",
        "abap", "x3", "plaintext",
    ]
}
