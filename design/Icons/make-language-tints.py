#!/usr/bin/env python3
"""Colours for language icons that have no colour of their own.

Some Devicon logos are black (Rust, Markdown…) and some languages have no logo at all (SQL, TOML…),
so in "Colour" mode they used to show in the text colour. This gives them the language's colour:
GitHub Linguist's (MIT, the colours of GitHub's language bars), or the brand colour from Simple Icons
(CC0) for frameworks Linguist doesn't list. Colours that are black, white or grey are left out, so those
icons keep the text colour. Each colour gets a light- and a dark-mode shade with the same hue, at
least 4:1 against the background (several logos are thin outlines, so 3:1 looked faint).

Devicon's Rust and Handlebars logos are fine outlines that turn into faint hairlines at list size, so
their single-colour versions are replaced with Simple Icons' bold glyphs (CC0). Run after
make-language-icons.py, which would put Devicon's back.

Usage: design/Icons/make-language-tints.py <linguist languages.yml> <simple-icons/_data/simple-icons.json> <linguist LICENSE>
       (github-linguist/linguist v9.4.0, npm package simple-icons@13.21.0)
Writes LanguageTints.swift, Resources/LINGUIST-LICENSE.txt and the bold glyphs.
"""
import colorsys, json, os, re, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FEATURES = os.path.join(ROOT, "Packages/ByteCacheKit/Sources/ByteCacheFeatures")
LIGHT_BACKGROUND, DARK_BACKGROUND = 0xFFFFFF, 0x1C1C1E

# Devicon logo name -> Simple Icons slug, for logos too thin to read at list size.
BOLD_GLYPHS = {"rust": "rust", "handlebars": "handlebarsdotjs"}

# Devicon logo name (darkLogos in LanguageIcons.swift) -> (source, name there)
LOGOS = {
    "rust": ("linguist", "Rust"), "markdown": ("linguist", "Markdown"), "solidity": ("linguist", "Solidity"),
    "handlebars": ("linguist", "Handlebars"), "coffeescript": ("linguist", "CoffeeScript"),
    "json": ("linguist", "JSON"), "crystal": ("linguist", "Crystal"), "purescript": ("linguist", "PureScript"),
    "cobol": ("linguist", "COBOL"), "ansible": ("simpleicons", "Ansible"), "latex": ("simpleicons", "LaTeX"),
    "django": ("simpleicons", "Django"), "flask": ("simpleicons", "Flask"), "nextjs": ("simpleicons", "Next.js"),
    "apachekafka": ("simpleicons", "Apache Kafka"), "unity": ("simpleicons", "Unity"),
}

# Language key (GENERIC in make-language-icons.py) -> Linguist name. PL/SQL takes SQL's colour: Linguist's
# own is a pale grey, and it's still SQL.
GENERIC = {
    "sql": "SQL", "tsql": "TSQL", "plsql": "SQL",
    "batch": "Batchfile", "cmd": "Batchfile", "shellsession": "Shell", "console": "Shell",
    "ini": "INI", "conf": "INI", "config": "INI", "toml": "TOML", "env": "Dotenv", "dotenv": "Dotenv",
    "properties": "Java Properties", "verilog": "Verilog", "systemverilog": "SystemVerilog", "vhdl": "VHDL",
    "plaintext": "Text", "text": "Text", "txt": "Text",
}


def linguist_colours(path):
    colours = {}
    for block in re.split(r"\n(?=[^\s#][^\n]*:\n)", open(path).read()):
        name = re.match(r'"?([^"\n]+?)"?:\n', block)
        colour = re.search(r'\n  color: "#([0-9a-fA-F]{6})"', block)
        if name and colour:
            colours[name.group(1)] = int(colour.group(1), 16)
    return colours


def simple_icons_colours(path):
    data = json.load(open(path))
    return {icon["title"]: int(icon["hex"], 16) for icon in (data["icons"] if isinstance(data, dict) else data)}


def rgb(value):
    return [((value >> shift) & 0xFF) / 255 for shift in (16, 8, 0)]


def luminance(value):
    channels = [c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb(value)]
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


def contrast(a, b):
    x, y = luminance(a), luminance(b)
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)


def shade(value, background, darker):
    """Same hue and saturation, lightness moved until it stands out from the background."""
    h, l, s = colorsys.rgb_to_hls(*rgb(value))
    while True:
        r, g, b = colorsys.hls_to_rgb(h, l, s)
        candidate = (round(r * 255) << 16) | (round(g * 255) << 8) | round(b * 255)
        if contrast(candidate, background) >= 4.1 or not 0 < l < 1:
            return candidate
        l = max(0, l - 0.01) if darker else min(1, l + 0.01)


def tint(value):
    if value is None:
        return None
    _, l, s = colorsys.rgb_to_hls(*rgb(value))
    if s < 0.15 or l < 0.08 or l > 0.97:  # black, white or grey: keep the text colour
        return None
    return shade(value, LIGHT_BACKGROUND, darker=True), shade(value, DARK_BACKGROUND, darker=False)


def write_swift(linguist, brands):
    def entries(table):
        lines = []
        for key, value in sorted(table.items()):
            if value:
                lines.append(f'        "{key}": Tint(light: 0x{value[0]:06X}, dark: 0x{value[1]:06X}),')
        return "\n".join(lines)

    logos = {k: tint((linguist if source == "linguist" else brands).get(name)) for k, (source, name) in LOGOS.items()}
    generic = {k: tint(linguist.get(name)) for k, name in GENERIC.items()}
    swift = f"""// Generated by design/Icons/make-language-tints.py from GitHub Linguist v9.4.0 (MIT) and Simple Icons 13.21.0 (CC0). Do not edit.

extension LanguageIcon {{
    /// Colour-mode tints for black logos, by Devicon logo name.
    static let logoTints: [String: Tint] = [
{entries(logos)}
    ]

    /// Colour-mode tints for languages shown with a generic icon, by language key.
    static let genericTints: [String: Tint] = [
{entries(generic)}
    ]
}}
"""
    open(os.path.join(FEATURES, "Icons/LanguageTints.swift"), "w").write(swift)
    return sum(1 for v in logos.values() if v), sum(1 for v in generic.values() if v)


def write_bold_glyphs(simple_icons_json):
    icons = os.path.join(os.path.dirname(os.path.dirname(simple_icons_json)), "icons")
    for logo, slug in BOLD_GLYPHS.items():
        svg = open(os.path.join(icons, f"{slug}.svg")).read()
        svg = re.sub(r"<title>.*?</title>", "", svg)
        svg = re.sub(r'\s*role="img"', "", svg)
        folder = os.path.join(FEATURES, f"Resources/Icons.xcassets/Languages/lang-{logo}-mono.imageset")
        name = next(f for f in os.listdir(folder) if f.endswith(".svg"))
        open(os.path.join(folder, name), "w").write(svg)


if __name__ == "__main__":
    linguist_path, simple_icons_path, licence_path = sys.argv[1:4]
    counts = write_swift(linguist_colours(linguist_path), simple_icons_colours(simple_icons_path))
    shutil.copy(licence_path, os.path.join(FEATURES, "Resources/LINGUIST-LICENSE.txt"))
    write_bold_glyphs(simple_icons_path)
    print(f"{counts[0]} logo tints, {counts[1]} generic tints")
