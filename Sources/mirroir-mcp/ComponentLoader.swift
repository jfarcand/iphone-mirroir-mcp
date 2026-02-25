// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Discovers and loads COMPONENT.md files from disk, merging with built-in catalog.
// ABOUTME: Search paths follow the same convention as skill files: project-local overrides global.

import Foundation
import HelperLib

/// Discovers and loads component definitions from disk and built-in catalog.
/// User-defined COMPONENT.md files override built-in definitions by name.
enum ComponentLoader {

    /// Load all component definitions: built-in catalog merged with any on-disk overrides.
    ///
    /// Disk files override built-in definitions with the same name.
    /// Project-local files override global files with the same name.
    ///
    /// - Returns: All component definitions, deduplicated by name.
    static func loadAll() -> [ComponentDefinition] {
        let diskDefinitions = loadFromDisk()
        let diskNames = Set(diskDefinitions.map { $0.name })

        // Start with disk definitions (they take priority), then add built-ins not overridden
        var result = diskDefinitions
        for builtIn in ComponentCatalog.definitions where !diskNames.contains(builtIn.name) {
            result.append(builtIn)
        }

        return result
    }

    /// Search paths for COMPONENT.md files, in resolution order.
    ///
    /// 1. `<cwd>/.mirroir-mcp/components/` (project-local)
    /// 2. `~/.mirroir-mcp/components/` (global)
    /// 3. `../mirroir-skills/components/ios/` (sibling skills repo, iOS)
    /// 4. `../mirroir-skills/components/custom/` (sibling skills repo, custom)
    static func searchPaths() -> [URL] {
        let cwd = FileManager.default.currentDirectoryPath
        let home = ("~" as NSString).expandingTildeInPath

        return [
            URL(fileURLWithPath: cwd + "/" + PermissionPolicy.configDirName + "/components"),
            URL(fileURLWithPath: home + "/" + PermissionPolicy.configDirName + "/components"),
            URL(fileURLWithPath: cwd + "/../mirroir-skills/components/ios"),
            URL(fileURLWithPath: cwd + "/../mirroir-skills/components/custom"),
        ]
    }

    // MARK: - Private

    /// Load COMPONENT.md files from all search paths.
    /// Earlier paths take priority when names collide.
    private static func loadFromDisk() -> [ComponentDefinition] {
        var seen = Set<String>()
        var definitions: [ComponentDefinition] = []

        for searchPath in searchPaths() {
            let files = findComponentFiles(in: searchPath)
            for fileURL in files {
                let stem = fileURL.deletingPathExtension().lastPathComponent
                guard !seen.contains(stem) else { continue }

                guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                    continue
                }

                let definition = ComponentSkillParser.parse(content: content, fallbackName: stem)
                seen.insert(definition.name)
                definitions.append(definition)
            }
        }

        return definitions
    }

    /// Find all `.md` files in a directory (non-recursive).
    private static func findComponentFiles(in dirURL: URL) -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dirURL.path) else { return [] }

        guard let contents = try? fm.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
