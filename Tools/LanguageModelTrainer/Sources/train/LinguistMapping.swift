/// GitHub Linguist `samples/<folder>` → ByteStash catalog id.
let linguistMapping: [String: String] = [
    "JavaScript": "javascript", "TypeScript": "typescript", "TSX": "typescript", "HTML": "html",
    "CSS": "css", "SCSS": "css", "Less": "css", "PHP": "php", "C": "c", "C++": "cpp", "C#": "csharp",
    "VBA": "vba", "Rust": "rust", "Go": "go", "Java": "java", "Kotlin": "kotlin", "Scala": "scala",
    "Groovy": "groovy", "Python": "python", "Ruby": "ruby", "Perl": "perl", "Lua": "lua", "Shell": "bash",
    "PowerShell": "powershell", "SQL": "sql", "PLpgSQL": "sql", "TSQL": "sql", "Markdown": "markdown",
    "YAML": "yaml", "Vim Script": "vimscript", "HCL": "terraform", "Swift": "swift", "R": "r",
    "Julia": "julia", "Dart": "dart", "Elm": "elm", "Apex": "apex", "Vyper": "vyper", "Verilog": "verilog",
    "SystemVerilog": "systemverilog", "TeX": "latex", "MATLAB": "matlab", "GraphQL": "graphql", "ABAP": "abap",
]

/// Ids the classifier learns. The rest are decided by rules only (structural stage / disambiguator)
/// or are too rare in permissively licensed code to train on.
let ruleOnlyIds: Set<String> = [
    "json", "xml", "dockerfile", "kubernetes", "toml", "ini", "conf", "plaintext", "x3", "webassembly",
    "batch", "mongodb", "cypher",
]
