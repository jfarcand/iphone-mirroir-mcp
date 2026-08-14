// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Formats classified screen components into the classify_screen tool's report.
// ABOUTME: Pure text shaping — no capture, no model, no protocol concerns.

import Foundation
import HelperLib

/// Renders classified components as the report `classify_screen` returns.
enum ScreenClassificationReport {
    /// Format `components` covering a screen of `elementCount` elements.
    static func format(components: [ScreenComponent], elementCount: Int) -> String {
        var lines: [String] = []
        lines.append("=== Screen Classification ===")
        lines.append("\(elementCount) OCR elements → \(components.count) components")
        lines.append("")

        guard !components.isEmpty else {
            lines.append("No components matched. The screen may not correspond to any "
                + "definition in the catalog.")
            return lines.joined(separator: "\n")
        }

        for (index, component) in components.enumerated() {
            lines.append("\(index + 1). \(component.definition.name)")
            lines.append("   y: \(Int(component.topY))–\(Int(component.bottomY))"
                + (component.hasChevron ? "  (chevron)" : ""))
            if let target = component.tapTarget {
                lines.append("   tap: \"\(target.text)\" at (\(Int(target.tapX)), \(Int(target.tapY)))")
            }
            let texts = component.elements.map(\.point.text).filter { !$0.isEmpty }
            if !texts.isEmpty {
                lines.append("   elements: \(texts.joined(separator: ", "))")
            }
        }

        return lines.joined(separator: "\n")
    }
}
