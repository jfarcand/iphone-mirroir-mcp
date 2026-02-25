// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Built-in catalog of iOS UI component definitions for BFS exploration.
// ABOUTME: Provides default component patterns so detection works without external COMPONENT.md files.

import Foundation

/// Built-in iOS UI component definitions for element grouping during BFS exploration.
/// These serve as defaults; users can override via COMPONENT.md files on disk.
enum ComponentCatalog {

    /// All built-in iOS component definitions.
    static let definitions: [ComponentDefinition] = [
        navigationBar,
        tabBarItem,
        tableRowDisclosure,
        tableRowDetail,
        toggleRow,
        sectionHeader,
        sectionFooter,
        summaryCard,
        actionButton,
        searchBar,
        segmentedControl,
        alertDialog,
        explanationText,
        pageTitle,
        emptyState,
        listItem,
    ]

    // MARK: - Navigation Chrome

    static let navigationBar = ComponentDefinition(
        name: "navigation-bar",
        platform: "ios",
        description: "Nav bar with back button, title, and optional action buttons at the top of the screen.",
        visualPattern: ["Back chevron or label on the left", "Title centered", "Action buttons on the right"],
        matchRules: ComponentMatchRules(
            rowHasChevron: nil,
            minElements: 1,
            maxElements: 4,
            maxRowHeightPt: 50,
            hasNumericValue: nil,
            zone: .navBar
        ),
        interaction: ComponentInteraction(
            clickable: false,
            clickTarget: .none,
            clickResult: .none,
            backAfterClick: false
        ),
        grouping: ComponentGrouping(
            absorbsSameRow: true,
            absorbsBelowWithinPt: 0,
            absorbCondition: .any
        )
    )

    static let tabBarItem = ComponentDefinition(
        name: "tab-bar-item",
        platform: "ios",
        description: "Tab bar button at the bottom of the screen for top-level navigation.",
        visualPattern: ["Short label", "Bottom 12% of screen", "Evenly spaced horizontally"],
        matchRules: ComponentMatchRules(
            rowHasChevron: nil,
            minElements: 1,
            maxElements: 6,
            maxRowHeightPt: 60,
            hasNumericValue: nil,
            zone: .tabBar
        ),
        interaction: ComponentInteraction(
            clickable: true,
            clickTarget: .centered,
            clickResult: .navigates,
            backAfterClick: false
        ),
        grouping: ComponentGrouping(
            absorbsSameRow: false,
            absorbsBelowWithinPt: 0,
            absorbCondition: .any
        )
    )

    // MARK: - Table Rows

    static let tableRowDisclosure = ComponentDefinition(
        name: "table-row-disclosure",
        platform: "ios",
        description: "Standard table row with disclosure chevron indicating navigation.",
        visualPattern: [
            "One or two text labels aligned left",
            "Optional detail text or value aligned right",
            "Chevron (>, ›) at the far right edge",
        ],
        matchRules: ComponentMatchRules(
            rowHasChevron: true,
            minElements: 1,
            maxElements: 4,
            maxRowHeightPt: 90,
            hasNumericValue: nil,
            zone: .content
        ),
        interaction: ComponentInteraction(
            clickable: true,
            clickTarget: .firstNavigation,
            clickResult: .navigates,
            backAfterClick: true
        ),
        grouping: ComponentGrouping(
            absorbsSameRow: true,
            absorbsBelowWithinPt: 0,
            absorbCondition: .any
        )
    )

    static let tableRowDetail = ComponentDefinition(
        name: "table-row-detail",
        platform: "ios",
        description: "Table row with label and value but no chevron, indicating non-navigable detail.",
        visualPattern: [
            "Label on the left",
            "Value or detail text on the right",
            "No chevron indicator",
        ],
        matchRules: ComponentMatchRules(
            rowHasChevron: false,
            minElements: 1,
            maxElements: 4,
            maxRowHeightPt: 90,
            hasNumericValue: nil,
            zone: .content
        ),
        interaction: ComponentInteraction(
            clickable: false,
            clickTarget: .none,
            clickResult: .none,
            backAfterClick: false
        ),
        grouping: ComponentGrouping(
            absorbsSameRow: true,
            absorbsBelowWithinPt: 0,
            absorbCondition: .any
        )
    )

    // MARK: - Toggle & State

    static let toggleRow = ComponentDefinition(
        name: "toggle-row",
        platform: "ios",
        description: "Row with a switch/toggle control that should be skipped during exploration.",
        visualPattern: ["Label on the left", "On/Off indicator on the right"],
        matchRules: ComponentMatchRules(
            rowHasChevron: false,
            minElements: 1,
            maxElements: 3,
            maxRowHeightPt: 90,
            hasNumericValue: nil,
            zone: .content
        ),
        interaction: ComponentInteraction(
            clickable: false,
            clickTarget: .none,
            clickResult: .toggles,
            backAfterClick: false
        ),
        grouping: ComponentGrouping(
            absorbsSameRow: true,
            absorbsBelowWithinPt: 0,
            absorbCondition: .any
        )
    )

    // MARK: - Section Structure

    static let sectionHeader = ComponentDefinition(
        name: "section-header",
        platform: "ios",
        description: "Section header text that labels a group of rows.",
        visualPattern: ["Short uppercase or title-case text", "Above a group of rows"],
        matchRules: ComponentMatchRules(
            rowHasChevron: nil,
            minElements: 1,
            maxElements: 2,
            maxRowHeightPt: 40,
            hasNumericValue: nil,
            zone: .content
        ),
        interaction: ComponentInteraction(
            clickable: false,
            clickTarget: .none,
            clickResult: .none,
            backAfterClick: false
        ),
        grouping: ComponentGrouping(
            absorbsSameRow: true,
            absorbsBelowWithinPt: 0,
            absorbCondition: .any
        )
    )

    static let sectionFooter = ComponentDefinition(
        name: "section-footer",
        platform: "ios",
        description: "Explanatory text below a group of rows, providing context about the section above.",
        visualPattern: ["Small text below a group of rows", "Often multiple lines"],
        matchRules: ComponentMatchRules(
            rowHasChevron: nil,
            minElements: 1,
            maxElements: 3,
            maxRowHeightPt: 80,
            hasNumericValue: nil,
            zone: .content
        ),
        interaction: ComponentInteraction(
            clickable: false,
            clickTarget: .none,
            clickResult: .none,
            backAfterClick: false
        ),
        grouping: ComponentGrouping(
            absorbsSameRow: true,
            absorbsBelowWithinPt: 50,
            absorbCondition: .infoOrDecorationOnly
        )
    )

    // MARK: - Cards & Rich Content

    static let summaryCard = ComponentDefinition(
        name: "summary-card",
        platform: "ios",
        description: "Card showing a metric with title, large numeric value, and optional chevron.",
        visualPattern: [
            "Title text on first line",
            "Large numeric value on second line",
            "Unit or description near the value",
            "Optional chevron for navigation",
        ],
        matchRules: ComponentMatchRules(
            rowHasChevron: nil,
            minElements: 2,
            maxElements: 6,
            maxRowHeightPt: 120,
            hasNumericValue: true,
            zone: .content
        ),
        interaction: ComponentInteraction(
            clickable: true,
            clickTarget: .firstNavigation,
            clickResult: .navigates,
            backAfterClick: true
        ),
        grouping: ComponentGrouping(
            absorbsSameRow: true,
            absorbsBelowWithinPt: 50,
            absorbCondition: .infoOrDecorationOnly
        )
    )

    // MARK: - Interactive Elements

    static let actionButton = ComponentDefinition(
        name: "action-button",
        platform: "ios",
        description: "Standalone button for triggering an action.",
        visualPattern: ["Centered text", "Button styling or distinct color"],
        matchRules: ComponentMatchRules(
            rowHasChevron: nil,
            minElements: 1,
            maxElements: 1,
            maxRowHeightPt: 60,
            hasNumericValue: nil,
            zone: .content
        ),
        interaction: ComponentInteraction(
            clickable: true,
            clickTarget: .centered,
            clickResult: .navigates,
            backAfterClick: true
        ),
        grouping: ComponentGrouping(
            absorbsSameRow: false,
            absorbsBelowWithinPt: 0,
            absorbCondition: .any
        )
    )

    static let searchBar = ComponentDefinition(
        name: "search-bar",
        platform: "ios",
        description: "Search field, typically near the top of the screen.",
        visualPattern: ["Search placeholder text", "Magnifying glass icon"],
        matchRules: ComponentMatchRules(
            rowHasChevron: nil,
            minElements: 1,
            maxElements: 2,
            maxRowHeightPt: 50,
            hasNumericValue: nil,
            zone: .content
        ),
        interaction: ComponentInteraction(
            clickable: true,
            clickTarget: .centered,
            clickResult: .navigates,
            backAfterClick: true
        ),
        grouping: ComponentGrouping(
            absorbsSameRow: true,
            absorbsBelowWithinPt: 0,
            absorbCondition: .any
        )
    )

    static let segmentedControl = ComponentDefinition(
        name: "segmented-control",
        platform: "ios",
        description: "Tab-like selector with 2-4 short labels for switching content views.",
        visualPattern: ["2-4 short labels in a row", "Evenly spaced", "One appears selected"],
        matchRules: ComponentMatchRules(
            rowHasChevron: nil,
            minElements: 2,
            maxElements: 4,
            maxRowHeightPt: 50,
            hasNumericValue: nil,
            zone: .content
        ),
        interaction: ComponentInteraction(
            clickable: true,
            clickTarget: .centered,
            clickResult: .navigates,
            backAfterClick: false
        ),
        grouping: ComponentGrouping(
            absorbsSameRow: true,
            absorbsBelowWithinPt: 0,
            absorbCondition: .any
        )
    )

    // MARK: - Modals & Overlays

    static let alertDialog = ComponentDefinition(
        name: "alert-dialog",
        platform: "ios",
        description: "Modal alert dialog with dismiss/confirm buttons.",
        visualPattern: ["Overlay on screen", "OK/Cancel/Allow/Deny buttons"],
        matchRules: ComponentMatchRules(
            rowHasChevron: nil,
            minElements: 1,
            maxElements: 4,
            maxRowHeightPt: 200,
            hasNumericValue: nil,
            zone: .content
        ),
        interaction: ComponentInteraction(
            clickable: true,
            clickTarget: .centered,
            clickResult: .dismisses,
            backAfterClick: false
        ),
        grouping: ComponentGrouping(
            absorbsSameRow: true,
            absorbsBelowWithinPt: 20,
            absorbCondition: .any
        )
    )

    // MARK: - Text Content

    static let explanationText = ComponentDefinition(
        name: "explanation-text",
        platform: "ios",
        description: "Informational paragraph that is not an interactive element.",
        visualPattern: ["Long text spanning most of the screen width", "Sentence-like content"],
        matchRules: ComponentMatchRules(
            rowHasChevron: nil,
            minElements: 1,
            maxElements: 3,
            maxRowHeightPt: 100,
            hasNumericValue: nil,
            zone: .content
        ),
        interaction: ComponentInteraction(
            clickable: false,
            clickTarget: .none,
            clickResult: .none,
            backAfterClick: false
        ),
        grouping: ComponentGrouping(
            absorbsSameRow: true,
            absorbsBelowWithinPt: 30,
            absorbCondition: .infoOrDecorationOnly
        )
    )

    static let pageTitle = ComponentDefinition(
        name: "page-title",
        platform: "ios",
        description: "Large title text at the top of a content screen.",
        visualPattern: ["Large text", "Top of content zone", "Short descriptive text"],
        matchRules: ComponentMatchRules(
            rowHasChevron: nil,
            minElements: 1,
            maxElements: 2,
            maxRowHeightPt: 60,
            hasNumericValue: nil,
            zone: .content
        ),
        interaction: ComponentInteraction(
            clickable: false,
            clickTarget: .none,
            clickResult: .none,
            backAfterClick: false
        ),
        grouping: ComponentGrouping(
            absorbsSameRow: true,
            absorbsBelowWithinPt: 0,
            absorbCondition: .any
        )
    )

    // MARK: - Special States

    static let emptyState = ComponentDefinition(
        name: "empty-state",
        platform: "ios",
        description: "Empty screen with centered text and optional call-to-action button.",
        visualPattern: ["Centered text", "Possibly an icon above", "Optional button below"],
        matchRules: ComponentMatchRules(
            rowHasChevron: nil,
            minElements: 1,
            maxElements: 4,
            maxRowHeightPt: 200,
            hasNumericValue: nil,
            zone: .content
        ),
        interaction: ComponentInteraction(
            clickable: false,
            clickTarget: .none,
            clickResult: .none,
            backAfterClick: false
        ),
        grouping: ComponentGrouping(
            absorbsSameRow: true,
            absorbsBelowWithinPt: 40,
            absorbCondition: .any
        )
    )

    static let listItem = ComponentDefinition(
        name: "list-item",
        platform: "ios",
        description: "Simple list item without chevron that may still be tappable.",
        visualPattern: ["Single label", "No chevron", "In a list context"],
        matchRules: ComponentMatchRules(
            rowHasChevron: false,
            minElements: 1,
            maxElements: 2,
            maxRowHeightPt: 90,
            hasNumericValue: nil,
            zone: .content
        ),
        interaction: ComponentInteraction(
            clickable: true,
            clickTarget: .firstNavigation,
            clickResult: .navigates,
            backAfterClick: true
        ),
        grouping: ComponentGrouping(
            absorbsSameRow: true,
            absorbsBelowWithinPt: 0,
            absorbCondition: .any
        )
    )
}
