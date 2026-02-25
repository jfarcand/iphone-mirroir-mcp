// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Unit tests for ComponentDetector: grouping OCR elements into UI components.
// ABOUTME: Verifies row matching, multi-row absorption, zone detection, and fallback behavior.

import XCTest
@testable import HelperLib
@testable import mirroir_mcp

final class ComponentDetectorTests: XCTestCase {

    // MARK: - Helpers

    private let screenHeight: Double = 890
    private let definitions = ComponentCatalog.definitions

    private func point(
        _ text: String, x: Double = 200, y: Double = 400
    ) -> TapPoint {
        TapPoint(text: text, tapX: x, tapY: y, confidence: 0.95)
    }

    private func classifiedNav(
        _ text: String, x: Double = 200, y: Double = 400, hasChevron: Bool = false
    ) -> ClassifiedElement {
        ClassifiedElement(
            point: point(text, x: x, y: y),
            role: .navigation,
            hasChevronContext: hasChevron
        )
    }

    private func classifiedInfo(
        _ text: String, x: Double = 200, y: Double = 400
    ) -> ClassifiedElement {
        ClassifiedElement(
            point: point(text, x: x, y: y),
            role: .info
        )
    }

    private func classifiedDeco(
        _ text: String, x: Double = 200, y: Double = 400
    ) -> ClassifiedElement {
        ClassifiedElement(
            point: point(text, x: x, y: y),
            role: .decoration
        )
    }

    // MARK: - Table Row Detection

    func testDetectsTableRowWithChevron() {
        let classified = [
            classifiedNav("General", x: 100, y: 400, hasChevron: true),
            classifiedDeco(">", x: 370, y: 400),
        ]

        let components = ComponentDetector.detect(
            classified: classified,
            definitions: definitions,
            screenHeight: screenHeight
        )

        // Should detect a table-row-disclosure component
        let disclosureRows = components.filter { $0.kind == "table-row-disclosure" }
        XCTAssertEqual(disclosureRows.count, 1,
            "Should detect one table-row-disclosure component")

        let row = disclosureRows[0]
        XCTAssertTrue(row.hasChevron)
        XCTAssertNotNil(row.tapTarget,
            "Disclosure row should have a tap target")
        XCTAssertEqual(row.tapTarget?.text, "General",
            "Tap target should be the navigation element, not the chevron")
        XCTAssertEqual(row.elements.count, 2,
            "Both label and chevron should be absorbed into the component")
    }

    func testDetectsMultipleTableRows() {
        let classified = [
            classifiedNav("General", x: 100, y: 300, hasChevron: true),
            classifiedDeco(">", x: 370, y: 300),
            classifiedNav("Privacy", x: 100, y: 380, hasChevron: true),
            classifiedDeco(">", x: 370, y: 380),
            classifiedNav("About", x: 100, y: 460, hasChevron: true),
            classifiedDeco(">", x: 370, y: 460),
        ]

        let components = ComponentDetector.detect(
            classified: classified,
            definitions: definitions,
            screenHeight: screenHeight
        )

        let disclosureRows = components.filter { $0.kind == "table-row-disclosure" }
        XCTAssertEqual(disclosureRows.count, 3,
            "Should detect three separate table-row-disclosure components")
    }

    // MARK: - Non-Clickable Components

    func testExplanationTextNotClickable() {
        let classified = [
            classifiedInfo(
                "This is a long explanation of the feature that helps users understand",
                x: 200, y: 400
            ),
        ]

        let components = ComponentDetector.detect(
            classified: classified,
            definitions: definitions,
            screenHeight: screenHeight
        )

        // All detected components for info text should not be clickable
        for component in components {
            if component.elements.allSatisfy({ $0.role == .info }) {
                XCTAssertNil(component.tapTarget,
                    "Info text component should not have a tap target")
            }
        }
    }

    // MARK: - Zone Detection

    func testNavBarZoneDetected() {
        // Elements in the top 12% of screen should match nav bar zone
        let classified = [
            classifiedNav("Settings", x: 200, y: 50),
        ]

        let rowProps = ComponentDetector.computeRowProperties(
            classified, screenHeight: screenHeight
        )

        XCTAssertEqual(rowProps.zone, .navBar,
            "Elements in top 12% should be in nav bar zone")
    }

    func testTabBarZoneDetected() {
        // Elements in the bottom 12% of screen should match tab bar zone
        let classified = [
            classifiedNav("Home", x: 100, y: 830),
        ]

        let rowProps = ComponentDetector.computeRowProperties(
            classified, screenHeight: screenHeight
        )

        XCTAssertEqual(rowProps.zone, .tabBar,
            "Elements in bottom 12% should be in tab bar zone")
    }

    func testContentZoneForMidScreenElements() {
        let classified = [
            classifiedNav("General", x: 100, y: 400),
        ]

        let rowProps = ComponentDetector.computeRowProperties(
            classified, screenHeight: screenHeight
        )

        XCTAssertEqual(rowProps.zone, .content,
            "Mid-screen elements should be in content zone")
    }

    // MARK: - Row Properties

    func testRowPropertiesDetectChevron() {
        let classified = [
            classifiedNav("General", x: 100, y: 400, hasChevron: true),
            classifiedDeco(">", x: 370, y: 400),
        ]

        let rowProps = ComponentDetector.computeRowProperties(
            classified, screenHeight: screenHeight
        )

        XCTAssertTrue(rowProps.hasChevron)
        XCTAssertEqual(rowProps.elementCount, 2)
    }

    func testRowPropertiesDetectNumericValue() {
        let classified = [
            classifiedInfo("12,4km", x: 200, y: 400),
        ]

        let rowProps = ComponentDetector.computeRowProperties(
            classified, screenHeight: screenHeight
        )

        XCTAssertTrue(rowProps.hasNumericValue,
            "Should detect numeric value in '12,4km'")
    }

    // MARK: - Multi-Row Absorption

    func testSummaryCardAbsorbsInfoBelow() {
        // Summary card with title + value, followed by info text within absorption range
        let classified = [
            classifiedNav("Distance", x: 100, y: 300),
            classifiedInfo("12,4km", x: 200, y: 300),
            classifiedInfo("marche et course", x: 200, y: 330),
        ]

        let components = ComponentDetector.detect(
            classified: classified,
            definitions: definitions,
            screenHeight: screenHeight
        )

        // The summary card or whatever matched should have absorbed the info text
        let multiElement = components.filter { $0.elements.count > 1 }
        XCTAssertFalse(multiElement.isEmpty,
            "Should have at least one multi-element component from absorption")
    }

    // MARK: - Fallback Behavior

    func testUnmatchedNavigationElementCreatesFallbackComponent() {
        // Use empty definitions so no definition can match — forces fallback path
        let classified = [
            classifiedNav("SomeUnusualElement", x: 200, y: 400),
        ]

        let components = ComponentDetector.detect(
            classified: classified,
            definitions: [],
            screenHeight: screenHeight
        )

        XCTAssertFalse(components.isEmpty,
            "Unmatched elements should create fallback components")
        XCTAssertEqual(components[0].kind, "unclassified")

        // The fallback should be clickable if the element was navigation
        let navComponents = components.filter { $0.tapTarget != nil }
        XCTAssertFalse(navComponents.isEmpty,
            "Navigation fallback should have a tap target")
    }

    func testUnmatchedInfoElementNotClickable() {
        // Use empty definitions so fallback path is taken
        let classified = [
            classifiedInfo("Some info text", x: 200, y: 400),
        ]

        let components = ComponentDetector.detect(
            classified: classified,
            definitions: [],
            screenHeight: screenHeight
        )

        XCTAssertEqual(components[0].kind, "unclassified")
        for component in components {
            XCTAssertNil(component.tapTarget,
                "Info element fallback should not have a tap target")
        }
    }

    // MARK: - Matching

    func testBestMatchPrefersSpecificDefinition() {
        // Row with chevron should match table-row-disclosure, not generic list-item
        let rowProps = ComponentDetector.RowProperties(
            elementCount: 2,
            hasChevron: true,
            hasNumericValue: false,
            rowHeight: 5,
            topY: 400,
            bottomY: 405,
            zone: .content,
            hasStateIndicator: false,
            hasLongText: false
        )

        let match = ComponentDetector.bestMatch(
            definitions: definitions,
            rowProps: rowProps
        )

        XCTAssertEqual(match?.name, "table-row-disclosure",
            "Row with chevron should match table-row-disclosure")
    }

    func testNoMatchForNavBarInContentZone() {
        // Navigation bar definition requires navBar zone, so content zone should not match
        let rowProps = ComponentDetector.RowProperties(
            elementCount: 2,
            hasChevron: false,
            hasNumericValue: false,
            rowHeight: 5,
            topY: 400,
            bottomY: 405,
            zone: .content,
            hasStateIndicator: false,
            hasLongText: false
        )

        let navBarDef = definitions.first { $0.name == "navigation-bar" }
        XCTAssertNotNil(navBarDef)

        // Verify navBar definition doesn't match content zone
        let match = ComponentDetector.bestMatch(
            definitions: [navBarDef!],
            rowProps: rowProps
        )

        XCTAssertNil(match,
            "Nav bar definition should not match content zone elements")
    }

    // MARK: - Empty Input

    func testEmptyClassifiedReturnsEmpty() {
        let components = ComponentDetector.detect(
            classified: [],
            definitions: definitions,
            screenHeight: screenHeight
        )

        XCTAssertTrue(components.isEmpty)
    }

    // MARK: - Sorted Output

    func testComponentsSortedByTopY() {
        let classified = [
            classifiedNav("Bottom", x: 100, y: 600, hasChevron: true),
            classifiedDeco(">", x: 370, y: 600),
            classifiedNav("Top", x: 100, y: 200, hasChevron: true),
            classifiedDeco(">", x: 370, y: 200),
            classifiedNav("Middle", x: 100, y: 400, hasChevron: true),
            classifiedDeco(">", x: 370, y: 400),
        ]

        let components = ComponentDetector.detect(
            classified: classified,
            definitions: definitions,
            screenHeight: screenHeight
        )

        // Components should be sorted by topY
        for i in 0..<(components.count - 1) {
            XCTAssertLessThanOrEqual(components[i].topY, components[i + 1].topY,
                "Components should be sorted by topY")
        }
    }

    // MARK: - Realistic Health App Screen

    func testHealthAppCardGrouping() {
        // Simulate the Health (Santé) app problem from the plan:
        // A single card "Distance (marche et course) / 12,4km" produces
        // 3-5 OCR elements. Component detection should group them.
        let elements = [
            TapPoint(text: "Distance", tapX: 50, tapY: 300, confidence: 0.9),
            TapPoint(text: "12,4", tapX: 200, tapY: 300, confidence: 0.9),
            TapPoint(text: "km", tapX: 240, tapY: 300, confidence: 0.9),
            TapPoint(text: "marche et course", tapX: 100, tapY: 330, confidence: 0.9),
            TapPoint(text: ">", tapX: 370, tapY: 315, confidence: 0.9),
        ]

        let classified = ElementClassifier.classify(
            elements, screenHeight: screenHeight
        )
        let components = ComponentDetector.detect(
            classified: classified,
            definitions: definitions,
            screenHeight: screenHeight
        )

        // Count clickable components — should be much fewer than raw elements
        let clickableComponents = components.filter { $0.tapTarget != nil }
        XCTAssertLessThan(clickableComponents.count, elements.count,
            "Component detection should reduce tap targets vs raw element count")
    }

    func testSettingsScreenGroupsRows() {
        // Simulate a Settings screen with typical iOS table rows
        let elements = [
            TapPoint(text: "General", tapX: 100, tapY: 300, confidence: 0.9),
            TapPoint(text: ">", tapX: 370, tapY: 300, confidence: 0.9),
            TapPoint(text: "Notifications", tapX: 100, tapY: 380, confidence: 0.9),
            TapPoint(text: ">", tapX: 370, tapY: 380, confidence: 0.9),
            TapPoint(text: "Privacy", tapX: 100, tapY: 460, confidence: 0.9),
            TapPoint(text: ">", tapX: 370, tapY: 460, confidence: 0.9),
        ]

        let classified = ElementClassifier.classify(
            elements, screenHeight: screenHeight
        )
        let components = ComponentDetector.detect(
            classified: classified,
            definitions: definitions,
            screenHeight: screenHeight
        )

        // Each row (label + chevron) should be one component
        let disclosureRows = components.filter { $0.kind == "table-row-disclosure" }
        XCTAssertEqual(disclosureRows.count, 3,
            "Each settings row with chevron should be detected as table-row-disclosure")

        // Each component should absorb both the label and the chevron
        for row in disclosureRows {
            XCTAssertEqual(row.elements.count, 2,
                "Disclosure row should absorb label + chevron")
        }

        // Tap targets should be the labels, not the chevrons
        let tapTexts = Set(disclosureRows.compactMap { $0.tapTarget?.text })
        XCTAssertTrue(tapTexts.contains("General"))
        XCTAssertTrue(tapTexts.contains("Notifications"))
        XCTAssertTrue(tapTexts.contains("Privacy"))
    }
}
