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

    public static func displayName(_ id: String) -> String {
        displayNames[id] ?? id.prefix(1).uppercased() + id.dropFirst()
    }

    /// File extension (with or without dot, any case) → id.
    public static func id(forExtension ext: String) -> String? {
        let key = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return extensionMap[key]
    }

    /// Common names (editor modes, shebang interpreters, Markdown fence tags) → id.
    public static func id(forAlias alias: String) -> String? {
        let key = alias.lowercased()
        if ids.contains(key) { return key }
        return aliasMap[key] ?? extensionMap[key]
    }

    /// Exact file names that identify a language without an extension.
    static let fileNames: [String: String] = [
        "dockerfile": "dockerfile", "containerfile": "dockerfile",
        ".bashrc": "bash", ".bash_profile": "bash", ".zshrc": "bash", ".profile": "bash",
        ".vimrc": "vimscript", "_vimrc": "vimscript", "gemfile": "ruby", "rakefile": "ruby",
        "jenkinsfile": "groovy", "cargo.lock": "toml", "pipfile": "toml",
    ]

    static let extensionMap: [String: String] = [
        "js": "javascript", "mjs": "javascript", "cjs": "javascript", "jsx": "javascript",
        "ts": "typescript", "tsx": "typescript", "mts": "typescript", "cts": "typescript",
        "html": "html", "htm": "html", "xhtml": "html",
        "css": "css", "scss": "css", "sass": "css", "less": "css",
        "php": "php", "phtml": "php", "wat": "webassembly", "wast": "webassembly",
        "c": "c", "h": "c", "cpp": "cpp", "cc": "cpp", "cxx": "cpp", "hpp": "cpp", "hh": "cpp", "hxx": "cpp",
        "cs": "csharp", "vba": "vba", "bas": "vba", "vbs": "vba",
        "rs": "rust", "go": "go", "java": "java", "kt": "kotlin", "kts": "kotlin",
        "scala": "scala", "sc": "scala", "groovy": "groovy", "gradle": "groovy",
        "py": "python", "pyw": "python", "pyi": "python", "rb": "ruby", "erb": "ruby",
        "pl": "perl", "pm": "perl", "lua": "lua",
        "sh": "bash", "bash": "bash", "zsh": "bash", "ksh": "bash",
        "ps1": "powershell", "psm1": "powershell", "psd1": "powershell", "bat": "batch", "cmd": "batch",
        "sql": "sql", "psql": "sql", "mongo": "mongodb", "md": "markdown", "markdown": "markdown", "mdx": "markdown",
        "yaml": "yaml", "yml": "yaml", "json": "json", "jsonc": "json", "geojson": "json",
        "xml": "xml", "xsd": "xml", "xsl": "xml", "plist": "xml", "svg": "xml",
        "toml": "toml", "ini": "ini", "cfg": "ini", "conf": "conf", "vim": "vimscript",
        "tf": "terraform", "tfvars": "terraform", "hcl": "terraform", "dockerfile": "dockerfile",
        "swift": "swift", "r": "r", "jl": "julia", "dart": "dart", "elm": "elm",
        "cls": "apex", "trigger": "apex", "sol": "solidity", "vy": "vyper",
        "v": "verilog", "vh": "verilog", "sv": "systemverilog", "svh": "systemverilog",
        "tex": "latex", "sty": "latex", "m": "matlab", "mat": "matlab",
        "graphql": "graphql", "gql": "graphql", "cypher": "cypher", "cql": "cypher", "abap": "abap",
        "txt": "plaintext", "text": "plaintext",
    ]

    static let aliasMap: [String: String] = [
        "node": "javascript", "nodejs": "javascript", "deno": "javascript", "bun": "javascript",
        "ecmascript": "javascript", "javascriptreact": "javascript", "js2": "javascript",
        "ts-node": "typescript", "typescriptreact": "typescript",
        "c++": "cpp", "cplusplus": "cpp", "objc": "c", "c#": "csharp", "dotnet": "csharp",
        "golang": "go", "python3": "python", "python2": "python", "py3": "python",
        "shell": "bash", "sh": "bash", "zsh": "bash", "ksh": "bash", "dash": "bash", "shell-script": "bash",
        "sh-mode": "bash", "pwsh": "powershell", "posh": "powershell", "dos": "batch", "bat": "batch",
        "postgres": "sql", "postgresql": "sql", "mysql": "sql", "sqlite": "sql", "plsql": "sql", "tsql": "sql",
        "mongo": "mongodb", "md": "markdown", "gfm": "markdown", "yml": "yaml",
        "hcl": "terraform", "docker": "dockerfile", "k8s": "kubernetes", "rscript": "r",
        "tex": "latex", "octave": "matlab", "gql": "graphql", "neo4j": "cypher", "viml": "vimscript",
        "vim": "vimscript", "text": "plaintext", "txt": "plaintext", "plain": "plaintext",
        // ByteStash's names for X3 4GL (Sage X3); its "src" alias is left out, too generic to trust.
        "x3src": "x3", "sage-x3": "x3", "4gl": "x3", "x3-4gl": "x3",
    ]

    static let displayNames: [String: String] = [
        "javascript": "JavaScript", "typescript": "TypeScript", "html": "HTML", "css": "CSS", "php": "PHP",
        "webassembly": "WebAssembly", "c": "C", "cpp": "C++", "csharp": "C#", "vba": "VBA", "go": "Go",
        "sql": "SQL", "mongodb": "MongoDB", "yaml": "YAML", "json": "JSON", "xml": "XML", "toml": "TOML",
        "ini": "INI", "conf": "Config", "vimscript": "Vim Script", "dockerfile": "Dockerfile",
        "powershell": "PowerShell", "graphql": "GraphQL", "latex": "LaTeX", "matlab": "MATLAB",
        "systemverilog": "SystemVerilog", "abap": "ABAP", "x3": "X3 4GL", "plaintext": "Plain Text", "r": "R",
    ]
}
