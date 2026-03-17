#!/usr/bin/env swift
import Foundation

struct PluginEntry: Decodable {
    let module: String
    let url: String?
    let from: String?
}

let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let pluginsFile = projectRoot.appendingPathComponent("plugins.json")
let outputFile = projectRoot
    .appendingPathComponent("Sources/StatusBar/Generated/PluginLoader.swift")

let data = try Data(contentsOf: pluginsFile)
let plugins = try JSONDecoder().decode([PluginEntry].self, from: data)

var lines: [String] = [
    "// This file is auto-generated from plugins.json.",
    "// Do not edit manually. Run `make generate` to regenerate.",
    "",
    "import StatusBarKit",
]

for plugin in plugins {
    lines.append("import \(plugin.module)")
}

lines += [
    "",
    "@MainActor",
    "enum PluginLoader {",
    "    static func registerAll(to registry: any WidgetRegistryProtocol) {",
]

for plugin in plugins {
    lines.append("        \(plugin.module)().register(to: registry)")
}

lines += [
    "    }",
    "}",
    "",
]

let code = lines.joined(separator: "\n")
try code.write(to: outputFile, atomically: true, encoding: .utf8)
print("Generated \(outputFile.path())")
