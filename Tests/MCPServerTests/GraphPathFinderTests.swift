// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Unit tests for GraphPathFinder: interesting path discovery and screen conversion.
// ABOUTME: Verifies leaf detection, path reconstruction, and ExploredScreen conversion.

import XCTest
@testable import HelperLib
@testable import mirroir_mcp

final class GraphPathFinderTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeElements(_ texts: [String], startY: Double = 120) -> [TapPoint] {
        texts.enumerated().map { (i, text) in
            TapPoint(text: text, tapX: 205, tapY: startY + Double(i) * 80, confidence: 0.95)
        }
    }

    /// Build a linear graph: root -> A -> B for testing
    private func buildLinearGraph() -> GraphSnapshot {
        let graph = NavigationGraph()
        graph.start(
            rootElements: makeElements(["Settings", "General"]),
            icons: [], hints: [], screenshot: "root_img", screenType: .settings
        )
        _ = graph.recordTransition(
            elements: makeElements(["About", "Name"]),
            icons: [], hints: [], screenshot: "a_img",
            actionType: "tap", elementText: "General", screenType: .list
        )
        _ = graph.recordTransition(
            elements: makeElements(["Version", "Build"]),
            icons: [], hints: [], screenshot: "b_img",
            actionType: "tap", elementText: "About", screenType: .detail
        )
        return graph.finalize()
    }

    /// Build a branching graph: root -> A, root -> B
    private func buildBranchingGraph() -> GraphSnapshot {
        let graph = NavigationGraph()
        let rootElements = makeElements(["Settings", "General", "Privacy"])
        graph.start(
            rootElements: rootElements, icons: [], hints: [],
            screenshot: "root_img", screenType: .settings
        )

        // Branch A: General -> About
        _ = graph.recordTransition(
            elements: makeElements(["About", "Name", "Version"]),
            icons: [], hints: [], screenshot: "a_img",
            actionType: "tap", elementText: "General", screenType: .list
        )

        // Go back to root
        _ = graph.recordTransition(
            elements: rootElements, icons: [], hints: [],
            screenshot: "root2_img", actionType: "press_key",
            elementText: "[", screenType: .settings
        )

        // Branch B: Privacy -> Location
        _ = graph.recordTransition(
            elements: makeElements(["Location Services", "Analytics"]),
            icons: [], hints: [], screenshot: "b_img",
            actionType: "tap", elementText: "Privacy", screenType: .list
        )

        return graph.finalize()
    }

    // MARK: - Empty Graph

    func testEmptyGraphReturnsNoPaths() {
        let snapshot = GraphSnapshot(nodes: [:], edges: [], rootFingerprint: "")

        let paths = GraphPathFinder.findInterestingPaths(in: snapshot)

        XCTAssertTrue(paths.isEmpty)
    }

    // MARK: - Linear Graph

    func testLinearGraphFindsLeafPath() {
        let snapshot = buildLinearGraph()

        let paths = GraphPathFinder.findInterestingPaths(in: snapshot)

        XCTAssertEqual(paths.count, 1, "Linear graph should produce one path to leaf")
        XCTAssertEqual(paths[0].edges.count, 2, "Path should have 2 edges: root->A, A->B")
    }

    func testLinearPathEdgeOrder() {
        let snapshot = buildLinearGraph()
        let paths = GraphPathFinder.findInterestingPaths(in: snapshot)

        guard let path = paths.first else {
            XCTFail("Expected at least one path")
            return
        }

        XCTAssertEqual(path.edges[0].elementText, "General")
        XCTAssertEqual(path.edges[1].elementText, "About")
    }

    // MARK: - Branching Graph

    func testBranchingGraphFindsTwoPaths() {
        let snapshot = buildBranchingGraph()

        let paths = GraphPathFinder.findInterestingPaths(in: snapshot)

        XCTAssertEqual(paths.count, 2, "Branching graph should produce two paths")
    }

    // MARK: - Path to ExploredScreens

    func testPathToExploredScreensLinear() {
        let snapshot = buildLinearGraph()
        let paths = GraphPathFinder.findInterestingPaths(in: snapshot)

        guard let path = paths.first else {
            XCTFail("Expected at least one path")
            return
        }

        let screens = GraphPathFinder.pathToExploredScreens(
            path: path.edges, snapshot: snapshot
        )

        XCTAssertEqual(screens.count, 3, "Should have root + 2 destination screens")
        XCTAssertNil(screens[0].actionType, "Root screen has no action")
        XCTAssertEqual(screens[1].actionType, "tap")
        XCTAssertEqual(screens[1].arrivedVia, "General")
        XCTAssertEqual(screens[2].actionType, "tap")
        XCTAssertEqual(screens[2].arrivedVia, "About")
    }

    func testPathToExploredScreensPreservesIndex() {
        let snapshot = buildLinearGraph()
        let paths = GraphPathFinder.findInterestingPaths(in: snapshot)

        guard let path = paths.first else {
            XCTFail("Expected at least one path")
            return
        }

        let screens = GraphPathFinder.pathToExploredScreens(
            path: path.edges, snapshot: snapshot
        )

        for (i, screen) in screens.enumerated() {
            XCTAssertEqual(screen.index, i,
                "Screen index should match position in array")
        }
    }

    func testEmptyPathProducesNoScreens() {
        let snapshot = buildLinearGraph()

        let screens = GraphPathFinder.pathToExploredScreens(
            path: [], snapshot: snapshot
        )

        XCTAssertTrue(screens.isEmpty)
    }

    // MARK: - Path Naming

    func testPathNameDerivedFromEdgeLabels() {
        let snapshot = buildLinearGraph()
        let paths = GraphPathFinder.findInterestingPaths(in: snapshot)

        guard let path = paths.first else {
            XCTFail("Expected at least one path")
            return
        }

        XCTAssertTrue(path.name.contains("general"),
            "Path name should include edge labels: got '\(path.name)'")
        XCTAssertTrue(path.name.contains("about"),
            "Path name should include edge labels: got '\(path.name)'")
    }

    // MARK: - Single Node Graph

    func testSingleNodeGraphReturnsNoPaths() {
        let graph = NavigationGraph()
        graph.start(
            rootElements: makeElements(["Settings"]),
            icons: [], hints: [], screenshot: "img", screenType: .settings
        )
        let snapshot = graph.finalize()

        let paths = GraphPathFinder.findInterestingPaths(in: snapshot)

        XCTAssertTrue(paths.isEmpty,
            "Single-node graph with no edges should produce no paths")
    }

    // MARK: - Screenshots Preserved

    func testPathToExploredScreensPreservesScreenshots() {
        let snapshot = buildLinearGraph()
        let paths = GraphPathFinder.findInterestingPaths(in: snapshot)
        guard let path = paths.first else {
            XCTFail("Expected a path")
            return
        }

        let screens = GraphPathFinder.pathToExploredScreens(
            path: path.edges, snapshot: snapshot
        )

        XCTAssertEqual(screens[0].screenshotBase64, "root_img")
        XCTAssertEqual(screens[1].screenshotBase64, "a_img")
        XCTAssertEqual(screens[2].screenshotBase64, "b_img")
    }
}
