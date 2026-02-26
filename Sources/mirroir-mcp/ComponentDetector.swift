// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Groups OCR elements into UI components using loaded component definitions.
// ABOUTME: Heuristic matching based on row properties, zone position, and element patterns.

import Foundation
import HelperLib

/// A detected UI component grouping one or more OCR elements.
struct ScreenComponent: Sendable {
    /// Component name from the matched definition (e.g. "table-row-disclosure").
    let kind: String
    /// The matched component definition.
    let definition: ComponentDefinition
    /// All OCR elements belonging to this component.
    let elements: [ClassifiedElement]
    /// Best element to tap (nil for non-interactive components).
    let tapTarget: TapPoint?
    /// Whether any element in this component is a chevron.
    let hasChevron: Bool
    /// Top Y coordinate of this component's bounding box.
    let topY: Double
    /// Bottom Y coordinate of this component's bounding box.
    let bottomY: Double
}

/// Groups classified OCR elements into UI components using loaded definitions.
/// Pure transformation: all static methods, no stored state.
enum ComponentDetector {

    /// Fraction of screen height defining the nav bar zone at the top.
    static let navBarZoneFraction: Double = 0.12
    /// Fraction of screen height defining the tab bar zone at the bottom.
    static let tabBarZoneFraction: Double = 0.12
    /// Numeric value regex for matching summary cards and value-containing components.
    private static let numericPattern = try! NSRegularExpression(
        pattern: #"\d+([.,]\d+)?"#
    )

    /// Group classified OCR elements into UI components using loaded definitions.
    ///
    /// Algorithm:
    /// 1. Zone partition (nav bar top ~12%, tab bar bottom ~12%, content middle)
    /// 2. Row grouping via ElementClassifier.groupIntoRows()
    /// 3. For each row, match against component definitions (most specific first)
    /// 4. Apply grouping rules to absorb adjacent rows into multi-row components
    /// 5. Unmatched elements become single-element components using their ClassifiedElement role
    ///
    /// - Parameters:
    ///   - classified: All classified elements on the screen.
    ///   - definitions: Loaded component definitions to match against.
    ///   - screenHeight: Height of the target window for zone calculation.
    /// - Returns: Detected components with grouped elements and tap targets.
    static func detect(
        classified: [ClassifiedElement],
        definitions: [ComponentDefinition],
        screenHeight: Double
    ) -> [ScreenComponent] {
        guard !classified.isEmpty else { return [] }

        let rows = ElementClassifier.groupIntoRows(
            classified.map { $0.point }
        )

        // Build row → classified elements mapping
        let classifiedByKey = buildClassifiedIndex(classified)
        let classifiedRows: [[ClassifiedElement]] = rows.map { row in
            row.compactMap { point in
                classifiedByKey[elementKey(point)]
            }
        }

        // Match each row against definitions, then absorb nearby rows
        var components: [ScreenComponent] = []
        var consumedRowIndices = Set<Int>()

        for (rowIndex, classifiedRow) in classifiedRows.enumerated() {
            guard !consumedRowIndices.contains(rowIndex) else { continue }
            guard !classifiedRow.isEmpty else { continue }

            let rowProps = computeRowProperties(
                classifiedRow, screenHeight: screenHeight
            )

            // Try matching against definitions (most specific first)
            if let match = bestMatch(
                definitions: definitions, rowProps: rowProps
            ) {
                var allElements = classifiedRow
                consumedRowIndices.insert(rowIndex)

                // Apply absorption rules to adjacent rows below
                if match.grouping.absorbsBelowWithinPt > 0 {
                    let maxY = rowProps.bottomY + match.grouping.absorbsBelowWithinPt
                    for belowIndex in (rowIndex + 1)..<classifiedRows.count {
                        guard !consumedRowIndices.contains(belowIndex) else { continue }
                        let belowRow = classifiedRows[belowIndex]
                        guard !belowRow.isEmpty else { continue }

                        let belowTopY = belowRow.map { $0.point.tapY }.min() ?? 0
                        guard belowTopY <= maxY else { break }

                        let canAbsorb = shouldAbsorb(
                            belowRow, condition: match.grouping.absorbCondition
                        )
                        if canAbsorb {
                            allElements.append(contentsOf: belowRow)
                            consumedRowIndices.insert(belowIndex)
                        }
                    }
                }

                let component = buildComponent(
                    kind: match.name, definition: match,
                    elements: allElements
                )
                components.append(component)
            } else {
                // No definition matched — create per-element fallback components
                consumedRowIndices.insert(rowIndex)
                for element in classifiedRow {
                    let fallback = buildFallbackComponent(element: element)
                    components.append(fallback)
                }
            }
        }

        return components.sorted { $0.topY < $1.topY }
    }

    // MARK: - Row Properties

    /// Properties computed from a row of classified elements for matching.
    struct RowProperties {
        let elementCount: Int
        let hasChevron: Bool
        let hasNumericValue: Bool
        let rowHeight: Double
        let topY: Double
        let bottomY: Double
        let zone: ScreenZone
        let hasStateIndicator: Bool
        let hasLongText: Bool
        let hasDismissButton: Bool
    }

    /// Compute properties for a row of classified elements.
    static func computeRowProperties(
        _ row: [ClassifiedElement],
        screenHeight: Double
    ) -> RowProperties {
        let ys = row.map { $0.point.tapY }
        let topY = ys.min() ?? 0
        let bottomY = ys.max() ?? 0
        let midY = (topY + bottomY) / 2

        let zone: ScreenZone
        if screenHeight > 0 && midY < screenHeight * navBarZoneFraction {
            zone = .navBar
        } else if screenHeight > 0 && midY > screenHeight * (1 - tabBarZoneFraction) {
            zone = .tabBar
        } else {
            zone = .content
        }

        let hasChevron = row.contains { element in
            ElementClassifier.chevronCharacters.contains(
                element.point.text.trimmingCharacters(in: .whitespaces)
            )
        }

        let hasNumericValue = row.contains { element in
            containsNumericValue(element.point.text)
        }

        let hasStateIndicator = row.contains { element in
            ElementClassifier.stateIndicators.contains(
                element.point.text.lowercased().trimmingCharacters(in: .whitespaces)
            )
        }

        let longTextThreshold = 50
        let hasLongText = row.contains { $0.point.text.count > longTextThreshold }

        let hasDismissButton = row.contains { element in
            ElementClassifier.dismissCharacters.contains(
                element.point.text.trimmingCharacters(in: .whitespaces)
            )
        }

        return RowProperties(
            elementCount: row.count,
            hasChevron: hasChevron,
            hasNumericValue: hasNumericValue,
            rowHeight: bottomY - topY,
            topY: topY,
            bottomY: bottomY,
            zone: zone,
            hasStateIndicator: hasStateIndicator,
            hasLongText: hasLongText,
            hasDismissButton: hasDismissButton
        )
    }

    // MARK: - Matching

    /// Score each definition against row properties, return the best match that passes
    /// all non-nil constraints. Returns nil if no definition matches.
    static func bestMatch(
        definitions: [ComponentDefinition],
        rowProps: RowProperties
    ) -> ComponentDefinition? {
        var bestDef: ComponentDefinition?
        var bestScore: Double = -1

        for definition in definitions {
            guard let score = scoreMatch(definition: definition, rowProps: rowProps) else {
                continue
            }
            if score > bestScore {
                bestScore = score
                bestDef = definition
            }
        }

        return bestDef
    }

    /// Score how well a definition matches row properties.
    /// Returns nil if any hard constraint fails; otherwise returns a specificity score.
    private static func scoreMatch(
        definition: ComponentDefinition,
        rowProps: RowProperties
    ) -> Double? {
        let rules = definition.matchRules
        var score: Double = 0

        // Hard constraint: zone must match
        if rules.zone != rowProps.zone {
            return nil
        }

        // Hard constraint: element count in range
        if rowProps.elementCount < rules.minElements || rowProps.elementCount > rules.maxElements {
            return nil
        }

        // Hard constraint: row height within limit
        if rowProps.rowHeight > rules.maxRowHeightPt {
            return nil
        }

        // Hard constraint: chevron requirement
        if let requireChevron = rules.rowHasChevron {
            if requireChevron != rowProps.hasChevron {
                return nil
            }
            // Chevron constraints are specific — bonus for matching
            score += 3.0
        }

        // Hard constraint: numeric value requirement
        if let requireNumeric = rules.hasNumericValue {
            if requireNumeric != rowProps.hasNumericValue {
                return nil
            }
            score += 2.0
        }

        // Hard constraint: long text requirement
        if let requireLongText = rules.hasLongText {
            if requireLongText != rowProps.hasLongText {
                return nil
            }
            score += 2.0
        }

        // Hard constraint: dismiss button requirement
        if let requireDismiss = rules.hasDismissButton {
            if requireDismiss != rowProps.hasDismissButton {
                return nil
            }
            score += 3.0
        }

        // Specificity bonuses: tighter ranges score higher
        let elementRange = rules.maxElements - rules.minElements
        if elementRange < 3 {
            score += 1.0
        }

        // Zone-specific bonus (nav bar and tab bar are more specific)
        if rules.zone == .navBar || rules.zone == .tabBar {
            score += 2.0
        }

        return score
    }

    // MARK: - Absorption

    /// Check whether a row of elements should be absorbed into a multi-row component.
    private static func shouldAbsorb(
        _ row: [ClassifiedElement],
        condition: AbsorbCondition
    ) -> Bool {
        switch condition {
        case .any:
            return true
        case .infoOrDecorationOnly:
            return row.allSatisfy { $0.role == .info || $0.role == .decoration }
        }
    }

    // MARK: - Component Building

    /// Build a ScreenComponent from matched definition and grouped elements.
    private static func buildComponent(
        kind: String,
        definition: ComponentDefinition,
        elements: [ClassifiedElement]
    ) -> ScreenComponent {
        let ys = elements.map { $0.point.tapY }
        let topY = ys.min() ?? 0
        let bottomY = ys.max() ?? 0

        let hasChevron = elements.contains { element in
            ElementClassifier.chevronCharacters.contains(
                element.point.text.trimmingCharacters(in: .whitespaces)
            )
        }

        let tapTarget = selectTapTarget(
            elements: elements,
            rule: definition.interaction.clickTarget,
            clickable: definition.interaction.clickable
        )

        return ScreenComponent(
            kind: kind,
            definition: definition,
            elements: elements,
            tapTarget: tapTarget,
            hasChevron: hasChevron,
            topY: topY,
            bottomY: bottomY
        )
    }

    /// Build a fallback single-element component when no definition matched.
    private static func buildFallbackComponent(
        element: ClassifiedElement
    ) -> ScreenComponent {
        let isClickable = element.role == .navigation
        let clickResult: ClickResult = element.hasChevronContext ? .navigates : .none

        let fallbackDef = ComponentDefinition(
            name: "unclassified",
            platform: "ios",
            description: "Element not matching any component definition.",
            visualPattern: [],
            matchRules: ComponentMatchRules(
                rowHasChevron: nil, minElements: 1, maxElements: 1,
                maxRowHeightPt: 100, hasNumericValue: nil, hasLongText: nil,
                hasDismissButton: nil, zone: .content
            ),
            interaction: ComponentInteraction(
                clickable: isClickable,
                clickTarget: isClickable ? .firstNavigation : .none,
                clickResult: clickResult,
                backAfterClick: clickResult == .navigates
            ),
            grouping: ComponentGrouping(
                absorbsSameRow: false,
                absorbsBelowWithinPt: 0,
                absorbCondition: .any
            )
        )

        return ScreenComponent(
            kind: "unclassified",
            definition: fallbackDef,
            elements: [element],
            tapTarget: isClickable ? element.point : nil,
            hasChevron: element.hasChevronContext,
            topY: element.point.tapY,
            bottomY: element.point.tapY
        )
    }

    /// Select the best tap target within a component's elements based on the click target rule.
    private static func selectTapTarget(
        elements: [ClassifiedElement],
        rule: ClickTargetRule,
        clickable: Bool
    ) -> TapPoint? {
        guard clickable else { return nil }

        switch rule {
        case .firstNavigation:
            // Prefer navigation-classified elements, then any non-decoration element
            if let nav = elements.first(where: { $0.role == .navigation }) {
                return nav.point
            }
            return elements.first(where: { $0.role != .decoration })?.point

        case .firstDismissButton:
            // Find the dismiss button (X, ✕, ×) in the component's elements
            if let dismiss = elements.first(where: { element in
                ElementClassifier.dismissCharacters.contains(
                    element.point.text.trimmingCharacters(in: .whitespaces)
                )
            }) {
                return dismiss.point
            }
            return elements.first(where: { $0.role != .decoration })?.point

        case .centered:
            // Pick the element closest to the horizontal center
            let sorted = elements.sorted { $0.point.tapX < $1.point.tapX }
            return sorted[sorted.count / 2].point

        case .none:
            return nil
        }
    }

    // MARK: - Helpers

    /// Check if text contains a numeric value (e.g. "12,4km", "3.2 GB", "50%").
    private static func containsNumericValue(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return numericPattern.firstMatch(in: text, range: range) != nil
    }

    /// Build an index of classified elements keyed by position-based key.
    private static func buildClassifiedIndex(
        _ classified: [ClassifiedElement]
    ) -> [String: ClassifiedElement] {
        var index: [String: ClassifiedElement] = [:]
        for element in classified {
            index[elementKey(element.point)] = element
        }
        return index
    }

    /// Position-based key for an element (matches ElementClassifier convention).
    private static func elementKey(_ point: TapPoint) -> String {
        "\(point.text)@\(Int(point.tapX)),\(Int(point.tapY))"
    }
}
