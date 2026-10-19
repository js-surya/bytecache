#!/usr/bin/env python3
"""Builds the language icons (CP-23) from Devicon (MIT, https://devicon.dev).

Usage: design/Icons/make-language-icons.py <path to devicon package>   (npm package devicon@2.17.0)

For each language it copies Devicon's colour SVG and a single-colour SVG into the asset catalog as
vector image sets ("lang-<name>-color" / "lang-<name>-mono", the latter a template image), detects
logos that are black (shown in the text colour in colour mode, or they'd vanish in dark mode), and
writes LanguageIcons.swift with the lookup tables. Languages without a logo use a generic AppSymbol.
"""
import json, os, re, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FEATURES = os.path.join(ROOT, "Packages/ByteCacheKit/Sources/ByteCacheFeatures")
ASSETS = os.path.join(FEATURES, "Resources/Icons.xcassets/Languages")
DEVICON_VERSION = "2.17.0"

# Normalised language name -> Devicon icon folder.
LOGOS = {
    # ByteStash's built-in languages
    "javascript": "javascript", "typescript": "typescript", "html": "html5", "css": "css3", "php": "php",
    "webassembly": "wasm", "c": "c", "cpp": "cplusplus", "csharp": "csharp", "vba": "visualbasic",
    "rust": "rust", "go": "go", "java": "java", "kotlin": "kotlin", "scala": "scala", "groovy": "groovy",
    "python": "python", "ruby": "ruby", "perl": "perl", "lua": "lua", "bash": "bash",
    "powershell": "powershell", "mongodb": "mongodb", "markdown": "markdown", "yaml": "yaml", "json": "json",
    "xml": "xml", "vimscript": "vim", "terraform": "terraform", "dockerfile": "docker",
    "kubernetes": "kubernetes", "swift": "swift", "r": "r", "julia": "julia", "dart": "dart", "elm": "elm",
    "apex": "salesforce", "solidity": "solidity", "vyper": "vyper", "latex": "latex", "matlab": "matlab",
    "graphql": "graphql", "cypher": "neo4j",
    # Other languages and tools people use as snippet languages
    "astro": "astro", "haskell": "haskell", "elixir": "elixir", "erlang": "erlang", "clojure": "clojure",
    "fsharp": "fsharp", "nix": "nixos", "svelte": "svelte", "vue": "vuejs", "react": "react", "sass": "sass",
    "less": "less", "nginx": "nginx", "objectivec": "objectivec", "zig": "zig", "ocaml": "ocaml",
    "crystal": "crystal", "nim": "nim", "fortran": "fortran", "cobol": "cobol", "prolog": "prolog",
    "racket": "racket", "gleam": "gleam", "jupyter": "jupyter", "nodejs": "nodejs", "bun": "bun",
    "angular": "angular", "nextjs": "nextjs", "tailwindcss": "tailwindcss", "bootstrap": "bootstrap",
    "jquery": "jquery", "django": "django", "flask": "flask", "rails": "rails", "laravel": "laravel",
    "spring": "spring", "dotnet": "dotnetcore", "unity": "unity", "godot": "godot", "arduino": "arduino",
    "cmake": "cmake", "gradle": "gradle", "maven": "maven", "ansible": "ansible", "jenkins": "jenkins",
    "githubactions": "githubactions", "gitlab": "gitlab", "git": "git", "linux": "linux",
    "android": "android", "azure": "azure", "aws": "amazonwebservices", "googlecloud": "googlecloud",
    "firebase": "firebase", "supabase": "supabase", "postgresql": "postgresql", "mysql": "mysql",
    "sqlite": "sqlite", "redis": "redis", "oracle": "oracle", "sqlserver": "microsoftsqlserver",
    "cassandra": "cassandra", "elasticsearch": "elasticsearch", "prometheus": "prometheus",
    "grafana": "grafana", "kafka": "apachekafka", "rabbitmq": "rabbitmq", "groovyscript": "groovy",
    "coffeescript": "coffeescript", "handlebars": "handlebars", "pug": "pug", "processing": "processing",
    "purescript": "purescript", "reasonml": "reasonml", "rstudio": "rstudio", "solidjs": "solidjs",
    "vitejs": "vitejs", "webpack": "webpack", "wordpress": "wordpress", "zsh": "bash",
}

# Normalised language name -> AppSymbol case for languages without a logo.
GENERIC = {
    "sql": "database", "plsql": "database", "tsql": "database",
    "batch": "terminal", "cmd": "terminal", "shellsession": "terminal", "console": "terminal",
    "plaintext": "plainText", "text": "plainText", "txt": "plainText",
    "ini": "configFile", "conf": "configFile", "toml": "configFile", "env": "configFile",
    "properties": "configFile", "config": "configFile", "dotenv": "configFile",
    "verilog": "chip", "systemverilog": "chip", "vhdl": "chip",
}

# Other spellings -> the names above.
ALIASES = {
    "js": "javascript", "mjs": "javascript", "cjs": "javascript", "ts": "typescript", "html5": "html",
    "css3": "css", "wasm": "webassembly", "c++": "cpp", "cplusplus": "cpp", "cc": "cpp", "c#": "csharp",
    "cs": "csharp", "f#": "fsharp", "vb": "vba", "visualbasic": "vba", "vbnet": "vba", "rs": "rust",
    "golang": "go", "kt": "kotlin", "py": "python", "python3": "python", "rb": "ruby", "pl": "perl",
    "sh": "bash", "shell": "bash", "shellscript": "bash", "ps1": "powershell", "pwsh": "powershell",
    "bat": "batch", "mongo": "mongodb", "md": "markdown", "yml": "yaml", "vim": "vimscript",
    "tf": "terraform", "hcl": "terraform", "docker": "dockerfile", "containerfile": "dockerfile",
    "k8s": "kubernetes", "tex": "latex", "gql": "graphql", "neo4j": "cypher", "objc": "objectivec",
    "jsx": "react", "tsx": "react", "scss": "sass", "node": "nodejs", "vuejs": "vue", "nixos": "nix",
    "ex": "elixir", "exs": "elixir", "erl": "erlang", "clj": "clojure", "hs": "haskell", "ml": "ocaml",
    "postgres": "postgresql", "psql": "postgresql", "mssql": "sqlserver", "ipynb": "jupyter",
    "ruby on rails": "rails", "rubyonrails": "rails", "net": "dotnet", "dotnetcore": "dotnet",
    "amazonwebservices": "aws", "gcp": "googlecloud", "apachekafka": "kafka", "tailwind": "tailwindcss",
    "next": "nextjs", "vite": "vitejs", "makefile": "cmake", "text/plain": "plaintext", "plain": "plaintext",
    "xhtml": "html", "svg": "xml", "jsonc": "json", "json5": "json",
}


def normalise(name):
    """Mirrors LanguageIcon.normalise in Swift."""
    return re.sub(r"[\s\-_.]", "", name.strip().lower())


def pick(folder, names):
    for n in names:
        p = os.path.join(folder, n)
        if os.path.exists(p):
            return p
    return None


def channels(hex_colour):
    h = hex_colour.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    return [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]


def is_dark_neutral(hex_colour):
    """Black or dark grey: dark and nearly colourless (a saturated red stays visible on black)."""
    c = channels(hex_colour)
    return max(c) < 0.45 and max(c) - min(c) < 0.15


def is_white(hex_colour):
    return min(channels(hex_colour)) > 0.9


def is_dark(svg_path):
    """A logo drawn only in black/grey (white details ignored) disappears on a dark background."""
    text = open(svg_path, encoding="utf-8").read()
    colours = re.findall(r"(?:fill|stop-color|stroke)\s*[:=]\s*[\"']?\s*(#[0-9a-fA-F]{3,6})\b", text)
    colours = [c for c in colours if not is_white(c)]
    if not colours:
        return True  # no colour set: SVG default is black
    return all(is_dark_neutral(c) for c in colours)


def write_imageset(name, svg, template):
    folder = os.path.join(ASSETS, f"{name}.imageset")
    os.makedirs(folder, exist_ok=True)
    shutil.copy(svg, os.path.join(folder, f"{name}.svg"))
    contents = {
        "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True,
                       "template-rendering-intent": "template" if template else "original"},
    }
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)


def main(package):
    icons = os.path.join(package, "icons")
    shutil.rmtree(ASSETS, ignore_errors=True)
    os.makedirs(ASSETS)
    with open(os.path.join(ASSETS, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)

    logos, dark, skipped = [], [], []
    for logo in sorted(set(LOGOS.values())):
        folder = os.path.join(icons, logo)
        # Square marks only: wordmarks (logo plus name) are unreadable at icon size.
        colour = pick(folder, [f"{logo}-original.svg", f"{logo}-plain.svg"])
        mono = pick(folder, [f"{logo}-plain.svg", f"{logo}-line.svg", f"{logo}-original.svg"])
        if not colour or not mono:
            skipped.append(logo)
            continue
        logos.append(logo)
        write_imageset(f"lang-{logo}-color", colour, template=False)
        write_imageset(f"lang-{logo}-mono", mono, template=True)
        if is_dark(colour):
            dark.append(logo)

    available = {k: v for k, v in LOGOS.items() if v in logos}

    def table(d, quote_values=True):
        rows = [f'        "{k}": {json.dumps(v) if quote_values else "." + v},' for k, v in sorted(d.items())]
        return "\n".join(rows)

    swift = f"""// Generated by design/Icons/make-language-icons.py from Devicon {DEVICON_VERSION} (MIT). Do not edit.

extension LanguageIcon {{
    static let logoByKey: [String: String] = [
{table(available)}
    ]

    static let genericByKey: [String: AppSymbol] = [
{table(GENERIC, quote_values=False)}
    ]

    static let aliases: [String: String] = [
{table({normalise(k): v for k, v in ALIASES.items()})}
    ]

    /// Every bundled logo (asset names lang-<name>-color / lang-<name>-mono).
    public static let allLogos: [String] = {json.dumps(logos)}

    /// Black or grey logos: drawn in the text colour even in colour mode.
    static let darkLogos: Set<String> = {json.dumps(sorted(dark))}
}}
"""
    with open(os.path.join(FEATURES, "Icons/LanguageIcons.swift"), "w") as f:
        f.write(swift)
    shutil.copy(os.path.join(package, "LICENSE"), os.path.join(FEATURES, "Resources/DEVICON-LICENSE.txt"))
    print(f"{len(logos)} logos ({len(dark)} dark), {len(GENERIC)} generic, {len(ALIASES)} aliases")
    if skipped:
        print("no square logo, falls back to </>:", ", ".join(skipped))


if __name__ == "__main__":
    main(sys.argv[1])
