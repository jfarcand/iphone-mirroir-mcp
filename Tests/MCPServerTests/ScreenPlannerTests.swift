// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Unit tests for ScreenPlanner: ranked exploration plans per screen.
// ABOUTME: Verifies scoring signals, visited element exclusion, and realistic Settings screen ordering.

import XCTest
@testable import HelperLib
@testable import mirroir_mcp

final class ScreenPlannerTests: XCTestCase {

    // MARK: - Helpers

    private func point(_ text: String, x: Double = 205, y: Double = 400) -> TapPoint {
        TapPoint(text: text, tapX: x, tapY: y, confidence: 0.95)
    }

    private func navElement(
        _ text: String, y: Double = 400, hasChevron: Bool = false
    ) -> ClassifiedElement {
        ClassifiedElement(
            point: point(text, y: y),
            role: .navigation,
            hasChevronContext: hasChevron
        )
    }

    private let screenHeight: Double = 890

    // MARK: - Chevron Context

    func testChevronElementScoredHigherThanFallback() {
        let classified = [
            navElement("Settings Menu Item", y: 300, hasChevron: false),
            navElement("General", y: 400, hasChevron: true),
        ]

        let plan = ScreenPlanner.buildPlan(
            classified: classified,
            visitedElements: [],
            scoutResults: [:],
            screenHeight: screenHeight
        )

        XCTAssertEqual(plan.count, 2)
        // Y-sorted: Settings (y=300) before General (y=400)
        XCTAssertEqual(plan[0].point.text, "Settings Menu Item")
        XCTAssertEqual(plan[1].point.text, "General")
        // Chevron element should have higher score (used as tiebreak for same-Y)
        XCTAssertGreaterThan(plan[1].score, plan[0].score)
    }

    // MARK: - Label Length

    func testShortLabelScoredHigherThanLong() {
        let classified = [
            navElement("This is a very long descriptive label text", y: 400, hasChevron: true),
            navElement("General", y: 500, hasChevron: true),
        ]

        let plan = ScreenPlanner.buildPlan(
            classified: classified,
            visitedElements: [],
            scoutResults: [:],
            screenHeight: screenHeight
        )

        // Y-sorted: long label (y=400) before General (y=500)
        XCTAssertEqual(plan[0].point.text, "This is a very long descriptive label text")
        // Short label should have higher score
        XCTAssertGreaterThan(plan[1].score, plan[0].score,
            "Short label should score higher than long label")
    }

    // MARK: - Screen Position

    func testMidScreenPositionBonus() {
        // Two elements with identical signals except Y position
        let topElement = navElement("TopItem", y: 100, hasChevron: true)
        let midElement = navElement("MidItem", y: 450, hasChevron: true)

        let plan = ScreenPlanner.buildPlan(
            classified: [topElement, midElement],
            visitedElements: [],
            scoutResults: [:],
            screenHeight: screenHeight
        )

        // Y-sorted: TopItem (y=100) before MidItem (y=450)
        XCTAssertEqual(plan[0].point.text, "TopItem")
        // Mid-screen bonus gives MidItem higher score
        XCTAssertGreaterThan(plan[1].score, plan[0].score,
            "Mid-screen element should have higher score")
    }

    // MARK: - Scout Results

    func testScoutNavigatedBoostsScore() {
        let classified = [
            navElement("About", y: 300, hasChevron: true),
            navElement("General", y: 400, hasChevron: true),
        ]

        let plan = ScreenPlanner.buildPlan(
            classified: classified,
            visitedElements: [],
            scoutResults: ["General": .navigated],
            screenHeight: screenHeight
        )

        // Y-sorted: About (y=300) before General (y=400)
        XCTAssertEqual(plan[0].point.text, "About")
        // Scout-confirmed should have highest score
        XCTAssertGreaterThan(plan[1].score, plan[0].score,
            "Scout-confirmed navigation should have highest score")
    }

    func testScoutNoChangePenalizesScore() {
        let classified = [
            navElement("Broken Link", y: 300, hasChevron: true),
            navElement("Working Link", y: 400, hasChevron: false),
        ]

        let plan = ScreenPlanner.buildPlan(
            classified: classified,
            visitedElements: [],
            scoutResults: ["Broken Link": .noChange],
            screenHeight: screenHeight
        )

        // Y-sorted: Broken Link (y=300) before Working Link (y=400)
        XCTAssertEqual(plan[0].point.text, "Broken Link")
        XCTAssertLessThan(plan[0].score, 0,
            "Scout noChange element should have negative score")
        XCTAssertGreaterThan(plan[1].score, plan[0].score,
            "Working link should score higher than broken link")
    }

    // MARK: - Visited Elements

    func testVisitedElementsExcludedFromPlan() {
        let classified = [
            navElement("General", y: 300, hasChevron: true),
            navElement("Privacy", y: 400, hasChevron: true),
            navElement("About", y: 500, hasChevron: true),
        ]

        let plan = ScreenPlanner.buildPlan(
            classified: classified,
            visitedElements: ["General", "About"],
            scoutResults: [:],
            screenHeight: screenHeight
        )

        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].point.text, "Privacy")
    }

    // MARK: - Classifier Filter Integration

    func testLongDescriptiveTextFilteredOut() {
        // Long text (> 50 chars) should be classified as .info by ElementClassifier,
        // so it won't appear in the plan at all
        let longText = "Your account, iCloud, media purchases, and more information here"
        let elements = [
            TapPoint(text: longText, tapX: 200, tapY: 300, confidence: 0.9),
            TapPoint(text: "General", tapX: 100, tapY: 400, confidence: 0.9),
            TapPoint(text: ">", tapX: 370, tapY: 400, confidence: 0.9),
        ]
        let classified = ElementClassifier.classify(elements)
        let plan = ScreenPlanner.buildPlan(
            classified: classified,
            visitedElements: [],
            scoutResults: [:],
            screenHeight: screenHeight
        )

        XCTAssertEqual(plan.count, 1,
            "Long descriptive text should be filtered by classifier")
        XCTAssertEqual(plan[0].point.text, "General")
    }

    func testSentenceLikeTextFilteredOut() {
        let elements = [
            TapPoint(text: "Photos, videos, and backups", tapX: 200, tapY: 300, confidence: 0.9),
            TapPoint(text: "Storage", tapX: 100, tapY: 400, confidence: 0.9),
            TapPoint(text: ">", tapX: 370, tapY: 400, confidence: 0.9),
        ]
        let classified = ElementClassifier.classify(elements)
        let plan = ScreenPlanner.buildPlan(
            classified: classified,
            visitedElements: [],
            scoutResults: [:],
            screenHeight: screenHeight
        )

        let planTexts = Set(plan.map(\.point.text))
        XCTAssertFalse(planTexts.contains("Photos, videos, and backups"),
            "Sentence-like text should be filtered by classifier")
    }

    func testHelpLinksFilteredOut() {
        let elements = [
            TapPoint(text: "Learn More about your privacy settings", tapX: 200, tapY: 300, confidence: 0.9),
            TapPoint(text: "Privacy", tapX: 100, tapY: 400, confidence: 0.9),
            TapPoint(text: ">", tapX: 370, tapY: 400, confidence: 0.9),
        ]
        let classified = ElementClassifier.classify(elements)
        let plan = ScreenPlanner.buildPlan(
            classified: classified,
            visitedElements: [],
            scoutResults: [:],
            screenHeight: screenHeight
        )

        let planTexts = Set(plan.map(\.point.text))
        XCTAssertFalse(planTexts.contains("Learn More about your privacy settings"),
            "Help links should be filtered by classifier")
    }

    // MARK: - Sort Order

    func testPlanSortedByDescendingScore() {
        let classified = [
            navElement("Low", y: 100, hasChevron: false),
            navElement("High", y: 450, hasChevron: true),
            navElement("Mid", y: 450, hasChevron: true),
        ]

        let plan = ScreenPlanner.buildPlan(
            classified: classified,
            visitedElements: [],
            scoutResults: ["High": .navigated],
            screenHeight: screenHeight
        )

        // Verify Y-ascending order (primary sort) with score tiebreaker
        for i in 0..<(plan.count - 1) {
            if plan[i].point.tapY == plan[i + 1].point.tapY {
                XCTAssertGreaterThanOrEqual(plan[i].score, plan[i + 1].score,
                    "Same-Y elements should be sorted by descending score")
            } else {
                XCTAssertLessThanOrEqual(plan[i].point.tapY, plan[i + 1].point.tapY,
                    "Plan should be sorted by ascending Y position")
            }
        }
    }

    // MARK: - Deterministic Ordering

    func testEqualScoreElementsSortedByYPosition() {
        // Two elements with identical scoring signals — Y tiebreaker should apply
        let classified = [
            navElement("Beta", y: 500, hasChevron: true),
            navElement("Alpha", y: 300, hasChevron: true),
        ]

        let plan = ScreenPlanner.buildPlan(
            classified: classified,
            visitedElements: [],
            scoutResults: [:],
            screenHeight: screenHeight
        )

        XCTAssertEqual(plan.count, 2)
        XCTAssertEqual(plan[0].score, plan[1].score,
            "Both elements should have equal scores for this test to be meaningful")
        XCTAssertEqual(plan[0].point.text, "Alpha",
            "Equal-score elements should be ordered by Y position (lower Y first)")
        XCTAssertLessThan(plan[0].point.tapY, plan[1].point.tapY,
            "First element should have lower Y than second")
    }

    func testEqualScoreComponentsSortedByYPosition() {
        // Two disclosure rows with equal scores at different Y positions
        let elements = [
            TapPoint(text: "Beta", tapX: 100, tapY: 500, confidence: 0.9),
            TapPoint(text: ">", tapX: 370, tapY: 500, confidence: 0.9),
            TapPoint(text: "Alpha", tapX: 100, tapY: 300, confidence: 0.9),
            TapPoint(text: ">", tapX: 370, tapY: 300, confidence: 0.9),
        ]

        let classified = ElementClassifier.classify(elements, screenHeight: screenHeight)
        let components = ComponentDetector.detect(
            classified: classified,
            definitions: ComponentCatalog.definitions,
            screenHeight: screenHeight
        )
        let plan = ScreenPlanner.buildComponentPlan(
            components: components,
            visitedElements: [],
            scoutResults: [:],
            screenHeight: screenHeight
        )

        XCTAssertEqual(plan.count, 2)
        XCTAssertEqual(plan[0].score, plan[1].score,
            "Both components should have equal scores for this test to be meaningful")
        XCTAssertEqual(plan[0].point.text, "Alpha",
            "Equal-score components should be ordered by Y position (lower Y first)")
    }

    // MARK: - Edge Cases

    func testEmptyNavigationReturnsEmptyPlan() {
        let classified = [
            ClassifiedElement(point: point("On"), role: .info),
            ClassifiedElement(point: point(">"), role: .decoration),
        ]

        let plan = ScreenPlanner.buildPlan(
            classified: classified,
            visitedElements: [],
            scoutResults: [:],
            screenHeight: screenHeight
        )

        XCTAssertTrue(plan.isEmpty,
            "No navigation elements should produce empty plan")
    }

    // MARK: - Realistic Settings Screen

    func testRealisticSettingsScreenPlan() {
        // Simulates a French Settings root where "Identifiant Apple" (banner at top)
        // should score lower than "General" (chevron-backed menu item mid-screen)
        let elements = [
            // Apple ID banner — no chevron, long-ish label, top of screen
            TapPoint(text: "Identifiant Apple", tapX: 200, tapY: 240, confidence: 0.9),
            // Navigation rows with chevrons
            TapPoint(text: "General", tapX: 100, tapY: 400, confidence: 0.9),
            TapPoint(text: ">", tapX: 370, tapY: 400, confidence: 0.9),
            TapPoint(text: "Confidentialite", tapX: 100, tapY: 480, confidence: 0.9),
            TapPoint(text: ">", tapX: 370, tapY: 480, confidence: 0.9),
            TapPoint(text: "Notifications", tapX: 100, tapY: 560, confidence: 0.9),
            TapPoint(text: ">", tapX: 370, tapY: 560, confidence: 0.9),
        ]

        let classified = ElementClassifier.classify(elements)
        let plan = ScreenPlanner.buildPlan(
            classified: classified,
            visitedElements: [],
            scoutResults: [:],
            screenHeight: screenHeight
        )

        // All navigation elements should be in the plan
        let planTexts = plan.map(\.point.text)
        XCTAssertTrue(planTexts.contains("General"))
        XCTAssertTrue(planTexts.contains("Confidentialite"))
        XCTAssertTrue(planTexts.contains("Notifications"))

        // Y-sorted: "Identifiant Apple" (y=240) before "General" (y=440)
        // but General (chevron) should have a higher score
        if planTexts.contains("Identifiant Apple"), planTexts.contains("General") {
            let appleIDScore = plan[planTexts.firstIndex(of: "Identifiant Apple")!].score
            let generalScore = plan[planTexts.firstIndex(of: "General")!].score
            XCTAssertGreaterThan(generalScore, appleIDScore,
                "\"General\" (chevron) should have higher score than \"Identifiant Apple\"")
        }

        // Verify chevron-backed items appear before fallback items
        let chevronItems = plan.filter {
            ["General", "Confidentialite", "Notifications"].contains($0.point.text)
        }
        for item in chevronItems {
            XCTAssertTrue(item.reason.contains("chevron"),
                "\(item.point.text) should have chevron in reason")
        }
    }

    // MARK: - Component-Based Plan Building

    func testBuildComponentPlanFiltersNonClickable() {
        let elements = [
            TapPoint(text: "General", tapX: 100, tapY: 400, confidence: 0.9),
            TapPoint(text: ">", tapX: 370, tapY: 400, confidence: 0.9),
            TapPoint(text: "This is explanatory text for the section above that describes the setting",
                     tapX: 200, tapY: 500, confidence: 0.9),
        ]

        let classified = ElementClassifier.classify(elements, screenHeight: screenHeight)
        let components = ComponentDetector.detect(
            classified: classified,
            definitions: ComponentCatalog.definitions,
            screenHeight: screenHeight
        )
        let plan = ScreenPlanner.buildComponentPlan(
            components: components,
            visitedElements: [],
            scoutResults: [:],
            screenHeight: screenHeight
        )

        let planTexts = Set(plan.map(\.point.text))
        XCTAssertTrue(planTexts.contains("General"),
            "Clickable disclosure row should appear in component plan")
        XCTAssertFalse(
            planTexts.contains("This is explanatory text for the section above that describes the setting"),
            "Non-clickable explanation text should be excluded from plan"
        )
    }

    func testBuildComponentPlanExcludesVisited() {
        let elements = [
            TapPoint(text: "General", tapX: 100, tapY: 300, confidence: 0.9),
            TapPoint(text: ">", tapX: 370, tapY: 300, confidence: 0.9),
            TapPoint(text: "Privacy", tapX: 100, tapY: 400, confidence: 0.9),
            TapPoint(text: ">", tapX: 370, tapY: 400, confidence: 0.9),
        ]

        let classified = ElementClassifier.classify(elements, screenHeight: screenHeight)
        let components = ComponentDetector.detect(
            classified: classified,
            definitions: ComponentCatalog.definitions,
            screenHeight: screenHeight
        )
        let plan = ScreenPlanner.buildComponentPlan(
            components: components,
            visitedElements: ["General"],
            scoutResults: [:],
            screenHeight: screenHeight
        )

        let planTexts = plan.map(\.point.text)
        XCTAssertFalse(planTexts.contains("General"),
            "Visited elements should be excluded")
        XCTAssertTrue(planTexts.contains("Privacy"),
            "Non-visited elements should be included")
    }

    func testVisitedUsesDisplayLabelNotRawText() {
        // Two summary-card-like components whose tap targets are both "icon"
        // (YOLO detection), but displayLabels differ ("Activité" vs "Pas").
        // Visiting "Activité" should NOT mark "Pas" as visited.
        let summaryDef = ComponentDefinition(
            name: "summary-card", platform: "ios",
            description: "Summary card with icon tap target.",
            visualPattern: ["Icon + label text"],
            matchRules: ComponentMatchRules(
                rowHasChevron: false, chevronMode: nil,
                minElements: 1, maxElements: 6,
                maxRowHeightPt: 90, hasNumericValue: nil,
                hasLongText: nil, hasDismissButton: nil,
                zone: .content, minConfidence: nil,
                excludeNumericOnly: nil, textPattern: nil
            ),
            interaction: ComponentInteraction(
                clickable: true, clickTarget: .firstNavigation,
                clickResult: .pushesScreen, backAfterClick: true,
                labelRule: .longestText
            ),
            exploration: ComponentExploration(
                explorable: true, role: .depthNavigation, priority: .normal
            ),
            grouping: ComponentGrouping(
                absorbsSameRow: false, absorbsBelowWithinPt: 0,
                absorbCondition: .any, splitMode: .none
            )
        )

        let comp1 = ScreenComponent(
            kind: "summary-card", definition: summaryDef,
            elements: [
                ClassifiedElement(point: TapPoint(text: "icon", tapX: 200, tapY: 300, confidence: 0.9),
                                  role: .navigation, hasChevronContext: true),
                ClassifiedElement(point: TapPoint(text: "O Activité", tapX: 80, tapY: 300, confidence: 0.9),
                                  role: .navigation, hasChevronContext: true),
            ],
            tapTarget: TapPoint(text: "icon", tapX: 200, tapY: 300, confidence: 0.9),
            hasChevron: true, topY: 300, bottomY: 300
        )
        let comp2 = ScreenComponent(
            kind: "summary-card", definition: summaryDef,
            elements: [
                ClassifiedElement(point: TapPoint(text: "icon", tapX: 200, tapY: 500, confidence: 0.9),
                                  role: .navigation, hasChevronContext: true),
                ClassifiedElement(point: TapPoint(text: "O Pas", tapX: 80, tapY: 500, confidence: 0.9),
                                  role: .navigation, hasChevronContext: true),
            ],
            tapTarget: TapPoint(text: "icon", tapX: 200, tapY: 500, confidence: 0.9),
            hasChevron: true, topY: 500, bottomY: 500
        )

        // Visit "O Activité" (the displayLabel, not the raw "icon" text)
        let plan = ScreenPlanner.buildComponentPlan(
            components: [comp1, comp2],
            visitedElements: ["O Activité"],
            scoutResults: [:],
            screenHeight: screenHeight
        )

        XCTAssertEqual(plan.count, 1,
            "Only one component should remain after visiting O Activité")
        XCTAssertEqual(plan[0].displayLabel, "O Pas",
            "O Pas should not be excluded when O Activité was visited")
    }

    func testBuildComponentPlanSortedByDescendingScore() {
        let elements = [
            TapPoint(text: "Low", tapX: 100, tapY: 100, confidence: 0.9),
            TapPoint(text: "High", tapX: 100, tapY: 450, confidence: 0.9),
            TapPoint(text: ">", tapX: 370, tapY: 450, confidence: 0.9),
        ]

        let classified = ElementClassifier.classify(elements, screenHeight: screenHeight)
        let components = ComponentDetector.detect(
            classified: classified,
            definitions: ComponentCatalog.definitions,
            screenHeight: screenHeight
        )
        let plan = ScreenPlanner.buildComponentPlan(
            components: components,
            visitedElements: [],
            scoutResults: [:],
            screenHeight: screenHeight
        )

        for i in 0..<(plan.count - 1) {
            XCTAssertGreaterThanOrEqual(plan[i].score, plan[i + 1].score,
                "Component plan should be sorted by descending score")
        }
    }

    // MARK: - Safe Y Boundary

    func testElementsBelowSafeYExcludedFromPlan() {
        // screenHeight=890, safeBottomMarginPt=62 → safe Y threshold = 828
        let classified = [
            navElement("Safe Item", y: 700, hasChevron: true),
            navElement("Unsafe Item", y: 840, hasChevron: true),
        ]

        let plan = ScreenPlanner.buildPlan(
            classified: classified,
            visitedElements: [],
            scoutResults: [:],
            screenHeight: screenHeight
        )

        let planTexts = plan.map(\.point.text)
        XCTAssertTrue(planTexts.contains("Safe Item"),
            "Element above safe Y should be in plan")
        XCTAssertFalse(planTexts.contains("Unsafe Item"),
            "Element below safe Y threshold should be excluded from plan")
    }

    func testElementsAboveSafeYIncluded() {
        // Element just below the threshold (y=827 < 890-62=828)
        let classified = [
            navElement("Just Safe", y: 827, hasChevron: true),
        ]

        let plan = ScreenPlanner.buildPlan(
            classified: classified,
            visitedElements: [],
            scoutResults: [:],
            screenHeight: screenHeight
        )

        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].point.text, "Just Safe",
            "Element just above safe Y threshold should be included")
    }

    func testElementsBelowSafeYExcludedFromComponentPlan() {
        let elements = [
            TapPoint(text: "Safe Row", tapX: 100, tapY: 400, confidence: 0.9),
            TapPoint(text: ">", tapX: 370, tapY: 400, confidence: 0.9),
            TapPoint(text: "Unsafe Row", tapX: 100, tapY: 840, confidence: 0.9),
            TapPoint(text: ">", tapX: 370, tapY: 840, confidence: 0.9),
        ]

        let classified = ElementClassifier.classify(elements, screenHeight: screenHeight)
        let components = ComponentDetector.detect(
            classified: classified,
            definitions: ComponentCatalog.definitions,
            screenHeight: screenHeight
        )
        let plan = ScreenPlanner.buildComponentPlan(
            components: components,
            visitedElements: [],
            scoutResults: [:],
            screenHeight: screenHeight
        )

        let planTexts = plan.map(\.point.text)
        XCTAssertTrue(planTexts.contains("Safe Row"),
            "Component above safe Y should be in plan")
        XCTAssertFalse(planTexts.contains("Unsafe Row"),
            "Component below safe Y threshold should be excluded from plan")
    }

    // MARK: - Tab Bar Exclusion

    func testTabBarElementsExcludedFromComponentPlan() {
        let elements = [
            TapPoint(text: "General", tapX: 100, tapY: 400, confidence: 0.9),
            TapPoint(text: ">", tapX: 370, tapY: 400, confidence: 0.9),
            // Tab bar items in bottom 12% of 890pt screen (y > 783)
            TapPoint(text: "Resume", tapX: 100, tapY: 845, confidence: 0.9),
            TapPoint(text: "Partage", tapX: 300, tapY: 846, confidence: 0.9),
        ]

        let classified = ElementClassifier.classify(elements, screenHeight: screenHeight)
        let components = ComponentDetector.detect(
            classified: classified,
            definitions: ComponentCatalog.definitions,
            screenHeight: screenHeight
        )
        let plan = ScreenPlanner.buildComponentPlan(
            components: components,
            visitedElements: [],
            scoutResults: [:],
            screenHeight: screenHeight
        )

        let planTexts = Set(plan.map(\.point.text))
        XCTAssertTrue(planTexts.contains("General"),
            "Content area element should be in plan")
        XCTAssertFalse(planTexts.contains("Resume"),
            "Tab bar item should not be in plan")
        XCTAssertFalse(planTexts.contains("Partage"),
            "Tab bar item should not be in plan")
    }

    func testBreadthNavigationExemptFromSafeYFilter() {
        // Tab bar items sit at the very bottom of the screen (y > screenHeight - 62pt).
        // breadth_navigation role should be exempt from the safe Y filter.
        let tabDef = ComponentDefinition(
            name: "tab-bar-item",
            platform: "ios",
            description: "Tab bar item.",
            visualPattern: [],
            matchRules: ComponentMatchRules(
                rowHasChevron: nil, chevronMode: nil, minElements: 1, maxElements: 6,
                maxRowHeightPt: 60, hasNumericValue: nil, hasLongText: nil,
                hasDismissButton: nil, zone: .tabBar,
                minConfidence: nil, excludeNumericOnly: nil, textPattern: nil
            ),
            interaction: ComponentInteraction(
                clickable: true, clickTarget: .firstText,
                clickResult: .switchesContext, backAfterClick: false,
                labelRule: .firstText
            ),
            exploration: ComponentExploration(
                explorable: true,
                role: .breadthNavigation,
                priority: .high
            ),
            grouping: ComponentGrouping(
                absorbsSameRow: false, absorbsBelowWithinPt: 0,
                absorbCondition: .any, splitMode: .none
            )
        )

        // Tab item at y=855 — below safe margin (890 - 62 = 828)
        let component = ScreenComponent(
            kind: "tab-bar-item",
            definition: tabDef,
            elements: [
                ClassifiedElement(
                    point: TapPoint(text: "Résumé", tapX: 100, tapY: 855, confidence: 0.9),
                    role: .navigation, hasChevronContext: false
                ),
            ],
            tapTarget: TapPoint(text: "Résumé", tapX: 100, tapY: 855, confidence: 0.9),
            hasChevron: false, topY: 855, bottomY: 855
        )

        let plan = ScreenPlanner.buildComponentPlan(
            components: [component],
            visitedElements: [],
            scoutResults: [:],
            screenHeight: screenHeight
        )

        XCTAssertEqual(plan.count, 1,
            "breadth_navigation should be exempt from safe Y filter")
        XCTAssertEqual(plan[0].point.text, "Résumé")
        XCTAssertTrue(plan[0].isBreadthNavigation,
            "breadth_navigation should be flagged on RankedElement")
    }

    func testNonBreadthComponentNotFlaggedAsBreadth() {
        // A normal navigational component should NOT have isBreadthNavigation set.
        let disclosureDef = ComponentDefinition(
            name: "table-row-disclosure",
            platform: "ios",
            description: "Settings row with chevron.",
            visualPattern: [],
            matchRules: ComponentMatchRules(
                rowHasChevron: nil, chevronMode: .required, minElements: 1, maxElements: 6,
                maxRowHeightPt: 60, hasNumericValue: nil, hasLongText: nil,
                hasDismissButton: nil, zone: .content,
                minConfidence: nil, excludeNumericOnly: nil, textPattern: nil
            ),
            interaction: ComponentInteraction(
                clickable: true, clickTarget: .firstText,
                clickResult: .pushesScreen, backAfterClick: true,
                labelRule: .firstText
            ),
            exploration: ComponentExploration(
                explorable: true,
                role: .depthNavigation,
                priority: .normal
            ),
            grouping: ComponentGrouping(
                absorbsSameRow: false, absorbsBelowWithinPt: 0,
                absorbCondition: .any, splitMode: .none
            )
        )

        let component = ScreenComponent(
            kind: "table-row-disclosure",
            definition: disclosureDef,
            elements: [
                ClassifiedElement(
                    point: TapPoint(text: "General", tapX: 100, tapY: 400, confidence: 0.9),
                    role: .navigation, hasChevronContext: true
                ),
            ],
            tapTarget: TapPoint(text: "General", tapX: 100, tapY: 400, confidence: 0.9),
            hasChevron: true, topY: 400, bottomY: 400
        )

        let plan = ScreenPlanner.buildComponentPlan(
            components: [component],
            visitedElements: [],
            scoutResults: [:],
            screenHeight: screenHeight
        )

        XCTAssertEqual(plan.count, 1)
        XCTAssertFalse(plan[0].isBreadthNavigation,
            "Non-breadth component should not have isBreadthNavigation set")
    }

    func testBuildComponentPlanRespectsScoutResults() {
        let elements = [
            TapPoint(text: "Works", tapX: 100, tapY: 300, confidence: 0.9),
            TapPoint(text: ">", tapX: 370, tapY: 300, confidence: 0.9),
            TapPoint(text: "Broken", tapX: 100, tapY: 400, confidence: 0.9),
            TapPoint(text: ">", tapX: 370, tapY: 400, confidence: 0.9),
        ]

        let classified = ElementClassifier.classify(elements, screenHeight: screenHeight)
        let components = ComponentDetector.detect(
            classified: classified,
            definitions: ComponentCatalog.definitions,
            screenHeight: screenHeight
        )
        let plan = ScreenPlanner.buildComponentPlan(
            components: components,
            visitedElements: [],
            scoutResults: ["Broken": .noChange, "Works": .navigated],
            screenHeight: screenHeight
        )

        XCTAssertEqual(plan[0].point.text, "Works",
            "Scout-confirmed navigation should rank first")
    }

    func testNonExplorableComponentsExcludedFromPlan() {
        // Toggle row is clickable (UI truth) but NOT explorable (exploration policy)
        let elements = [
            TapPoint(text: "Général", tapX: 100, tapY: 300, confidence: 0.9),
            TapPoint(text: ">", tapX: 370, tapY: 300, confidence: 0.9),
        ]
        let classified = ElementClassifier.classify(elements, screenHeight: screenHeight)
        let components = ComponentDetector.detect(
            classified: classified,
            definitions: ComponentCatalog.definitions,
            screenHeight: screenHeight
        )

        // Verify that all components in the plan are explorable
        let plan = ScreenPlanner.buildComponentPlan(
            components: components,
            visitedElements: [],
            scoutResults: [:],
            screenHeight: screenHeight
        )

        // Every element in the plan should come from an explorable component
        for entry in plan {
            let source = components.first { $0.tapTarget?.text == entry.point.text }
            XCTAssertTrue(source?.definition.exploration.explorable ?? false,
                "Plan entry '\(entry.point.text)' should come from an explorable component")
        }
    }

    // MARK: - displayLabel Wiring

    func testComponentPlanCarriesDisplayLabel() {
        // Build a component with first_text label rule whose tapTarget differs from displayLabel
        let definition = ComponentDefinition(
            name: "tab-bar-item",
            platform: "ios",
            description: "Tab with icon and text",
            visualPattern: [],
            matchRules: ComponentMatchRules(
                rowHasChevron: nil, chevronMode: nil,
                minElements: 1, maxElements: 3,
                maxRowHeightPt: 60,
                hasNumericValue: nil, hasLongText: nil, hasDismissButton: nil,
                zone: .tabBar, minConfidence: 0.5,
                excludeNumericOnly: false, textPattern: nil
            ),
            interaction: ComponentInteraction(
                clickable: true, clickTarget: .centered,
                clickResult: .switchesContext, backAfterClick: false,
                labelRule: .firstText
            ),
            exploration: ComponentExploration(
                explorable: true, role: .breadthNavigation, priority: .high
            ),
            grouping: ComponentGrouping(
                absorbsSameRow: true, absorbsBelowWithinPt: 0,
                absorbCondition: .any, splitMode: .perItem
            )
        )

        // The tap target is "icon" but the first non-decoration text is "Home"
        // Use Y=400 to avoid safe bottom margin exclusion (safeBottomMarginPt=62)
        let component = ScreenComponent(
            kind: "tab-bar-item",
            definition: definition,
            elements: [
                ClassifiedElement(
                    point: TapPoint(text: "icon", tapX: 50, tapY: 400, confidence: 0.8),
                    role: .navigation, hasChevronContext: false
                ),
                ClassifiedElement(
                    point: TapPoint(text: "Home", tapX: 50, tapY: 410, confidence: 0.9),
                    role: .navigation, hasChevronContext: false
                ),
            ],
            tapTarget: TapPoint(text: "icon", tapX: 50, tapY: 400, confidence: 0.8),
            hasChevron: false,
            topY: 400,
            bottomY: 410
        )

        let plan = ScreenPlanner.buildComponentPlan(
            components: [component],
            visitedElements: [],
            scoutResults: [:],
            screenHeight: 890
        )

        XCTAssertEqual(plan.count, 1)
        // Raw tap target is "icon" but displayLabel should be "Home" (firstText rule)
        XCTAssertEqual(plan[0].point.text, "icon", "Tap target should be raw OCR text")
        XCTAssertEqual(plan[0].displayLabel, "Home",
            "displayLabel should use firstText label rule, not raw tap target")
    }

    // MARK: - Q-Value Boost Breadth-Front Invariant

    func testApplyQBoostKeepsBreadthItemsInFront() {
        let tab = RankedElement(
            point: point("", x: 205, y: 846), score: 6.0,
            reason: "tab-synth(Reels@2,horizontal)",
            displayLabel: "Reels", isBreadthNavigation: true)
        let feedItem = RankedElement(
            point: point("Suggested post", y: 300), score: 6.5,
            reason: "nav", displayLabel: "Suggested post")

        let boosted = ScreenPlanner.applyQBoost(
            plan: [tab, feedItem], qValues: ["Suggested post": 1.0])

        // q=1.0 boosts the feed item to 8.5, above the tab's 6.0 — the breadth
        // tab must still lead the plan, un-boosted.
        XCTAssertEqual(boosted.count, 2)
        XCTAssertEqual(boosted[0].displayLabel, "Reels")
        XCTAssertEqual(boosted[0].score, 6.0,
            "Breadth items must not receive a Q-boost")
        XCTAssertEqual(boosted[1].displayLabel, "Suggested post")
        XCTAssertGreaterThanOrEqual(boosted[1].score, 8.0,
            "Non-breadth item should carry the Q-boosted score")
    }

    func testApplyQBoostPreservesDeclaredTabOrder() {
        let declaredOrder = ["Accueil", "Recherche", "Reels"]
        let tabs = declaredOrder.enumerated().map { index, name in
            RankedElement(
                point: point("", x: Double(41 + index * 82), y: 846), score: 6.0,
                reason: "tab-synth(\(name)@\(index),horizontal)",
                displayLabel: name, isBreadthNavigation: true)
        }
        // Q-values increasing in reverse declared order — a score re-sort would
        // flip the tabs to Reels, Recherche, Accueil.
        let qValues = ["Accueil": 0.0, "Recherche": 2.0, "Reels": 5.0]

        let boosted = ScreenPlanner.applyQBoost(plan: tabs, qValues: qValues)

        XCTAssertEqual(boosted.map { $0.displayLabel }, declaredOrder,
            "Breadth tabs must keep their declared relative order")
    }
}
