// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Generates a markdown manifest index listing all skills produced from an exploration session.
// ABOUTME: Provides a summary document linking to individual skill files.

import Foundation

/// Generates a markdown manifest document indexing all skills from an exploration session.
enum SkillManifestGenerator {

    /// Generate a markdown manifest listing all skills.
    ///
    /// - Parameters:
    ///   - appName: The app that was explored.
    ///   - skills: Array of (name, content) tuples for each generated skill.
    /// - Returns: A markdown string with a numbered index of all skills.
    static func generate(
        appName: String,
        skills: [(name: String, content: String)]
    ) -> String {
        var lines: [String] = []
        lines.append("# \(appName) — \(skills.count) skills from exploration")
        lines.append("")
        for (i, skill) in skills.enumerated() {
            let filename = sanitizeFilename(skill.name)
            lines.append("\(i + 1). **\(skill.name)** — `\(filename).md`")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Sanitize a skill name into a valid filename.
    /// Converts to lowercase, replaces spaces and special chars with hyphens,
    /// collapses multiple hyphens, and trims leading/trailing hyphens.
    static func sanitizeFilename(_ name: String) -> String {
        let lowered = name.lowercased()
        let sanitized = lowered.map { char -> Character in
            if char.isLetter || char.isNumber || char == "-" {
                return char
            }
            return "-"
        }
        let joined = String(sanitized)
        // Collapse multiple hyphens into one
        let collapsed = joined.replacingOccurrences(
            of: "-+", with: "-",
            options: .regularExpression
        )
        // Trim leading/trailing hyphens
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
