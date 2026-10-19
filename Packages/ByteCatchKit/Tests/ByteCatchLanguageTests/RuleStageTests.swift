import XCTest
@testable import ByteCatchLanguage

final class RuleStageTests: XCTestCase {
    private func hint(_ text: String = "x", file: String? = nil, url: String? = nil) -> String? {
        HintStage().detect(DetectionInput(text: text, fileName: file, sourceURL: url.flatMap(URL.init(string:))))
    }

    func testCatalogLookups() {
        XCTAssertEqual(LanguageCatalog.id(forExtension: "TSX"), "typescript")
        XCTAssertEqual(LanguageCatalog.id(forExtension: ".py"), "python")
        XCTAssertEqual(LanguageCatalog.id(forAlias: "sh"), "bash")
        XCTAssertEqual(LanguageCatalog.id(forAlias: "c++"), "cpp")
        XCTAssertEqual(LanguageCatalog.displayName("cpp"), "C++")
        XCTAssertEqual(LanguageCatalog.displayName("javascript"), "JavaScript")
        XCTAssertNil(LanguageCatalog.id(forExtension: "zzz"))
        for id in LanguageCatalog.extensionMap.values { XCTAssertTrue(LanguageCatalog.ids.contains(id), id) }
    }

    func testHints() {
        XCTAssertEqual(hint(file: "deploy.tsx"), "typescript")
        XCTAssertEqual(hint(url: "https://raw.githubusercontent.com/a/b/main/x.py"), "python")
        XCTAssertEqual(hint(url: "https://gist.github.com/u/abc123#file-run-sh"), "bash")
        XCTAssertEqual(hint(file: "Dockerfile"), "dockerfile")
        XCTAssertEqual(hint(file: "main.tf"), "terraform")
        XCTAssertEqual(hint("puts 1\n# vim: ft=ruby"), "ruby")
        XCTAssertEqual(hint("-- -*- mode: lua -*-\nprint(1)"), "lua")
        XCTAssertNil(hint(file: "notes.zzz"))
        XCTAssertNil(hint(file: "gistfile1.txt"), ".txt says nothing about the language; let the code decide")
        XCTAssertNil(hint(url: "https://stackoverflow.com/questions/123/how-to"))
    }

    func testShebang() {
        let stage = ShebangStage()
        let cases: [(String, String?)] = [
            ("#!/usr/bin/env python3\nprint(1)", "python"),
            ("#!/bin/zsh\necho hi", "bash"),
            ("#!/usr/bin/env node\nconsole.log(1)", "javascript"),
            ("#!/usr/bin/env pwsh\nWrite-Host hi", "powershell"),
            ("#!/usr/bin/perl -w\nprint 1;", "perl"),
            ("echo hi", nil),
        ]
        for (text, want) in cases { XCTAssertEqual(stage.detect(DetectionInput(text: text)), want, text) }
    }

    func testStructural() {
        let stage = StructuralStage()
        let cases: [(String, String?)] = [
            (#"{"a": [1, 2]}"#, "json"),
            (#"<?xml version="1.0"?><a/>"#, "xml"),
            ("<!DOCTYPE html>\n<html></html>", "html"),
            ("<?php echo 1;", "php"),
            ("package main\n\nimport \"fmt\"", "go"),
            ("FROM node:20\nRUN npm ci", "dockerfile"),
            ("apiVersion: apps/v1\nkind: Deployment", "kubernetes"),
            ("---\nname: x\nlist:\n  - a", "yaml"),
            ("[server]\nport = 80\nname = \"x\"", "toml"),
            ("SELECT id FROM users WHERE x = 1;", "sql"),
            ("# Title\n\n- item\n\n[link](http://x)", "markdown"),
            ("Just some prose about code.", nil),
            ("x = 1", nil),
        ]
        for (text, want) in cases { XCTAssertEqual(stage.detect(DetectionInput(text: text)), want, text) }
    }

    func testStructuralLeavesOrdinaryCodeToClassifier() {
        let stage = StructuralStage()
        let code = [
            "def f(x):\n    return x\n\nprint(f(1))",
            "# install deps\necho hi\nnpm ci",
            "const a = {b: 1};\nconsole.log(a);",
            "package com.example;\n\nimport java.util.List;",
            "name: str = \"x\"\nage: int = 3\nprint(name)",
            "fn main() {\n    println!(\"hi\");\n}",
            "update(state);\nselect(item);",
        ]
        for text in code { XCTAssertNil(stage.detect(DetectionInput(text: text)), text) }
    }

    func testINIVersusTOML() {
        let stage = StructuralStage()
        XCTAssertEqual(stage.detect(DetectionInput(text: "[core]\neditor = vim\nautocrlf = input")), "ini")
        XCTAssertEqual(stage.detect(DetectionInput(text: "[package]\nname = \"bytecatch\"\nversion = \"0.1.0\"\n\n[dependencies]\nserde = { version = \"1\" }")), "toml")
    }

    func testMarkdownAndYAMLDoNotFireOnCodeThatLooksLikeThem() {
        let stage = StructuralStage()
        let code = [
            "owner: public(address)\nbalance: HashMap[address, uint256]\ntotal: uint256", // Vyper
            "  /** Returns the sum.\n   *\n   * # Example\n   * - see [[List]] and [docs](http://x)\n   */", // Scaladoc
            "\"\"\"\n# Arguments\n- `x`: input\n\nSee [docs](https://julialang.org).\n\"\"\"", // Julia docstring
            "foo(a: 1,\n    b: 2,\n    c: 3)", // Ruby keyword args
        ]
        for text in code { XCTAssertNil(stage.detect(DetectionInput(text: text)), text) }
    }
}
