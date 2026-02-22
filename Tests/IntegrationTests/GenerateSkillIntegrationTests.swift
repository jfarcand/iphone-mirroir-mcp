// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
// ABOUTME: Integration tests for the generate_skill pipeline against the FakeMirroring app.
// ABOUTME: Exercises ExplorationSession, ScreenFingerprint, and SkillMdGenerator with real OCR data.

import XCTest
@testable import HelperLib
@testable import mirroir_mcp

/// Integration tests for the generate_skill exploration pipeline.
/// Verifies that real OCR output flows correctly through ExplorationSession's
/// fingerprint-based dedup and SkillMdGenerator's SKILL.md assembly.
///
/// Run with: `swift test --filter IntegrationTests`
///
/// FakeMirroring must be running:
///   `swift build -c release --product FakeMirroring && ./scripts/package-fake-app.sh`
///   `open .build/release/FakeMirroring.app`
final class GenerateSkillIntegrationTests: XCTestCase {

    private var bridge: MirroringBridge!
    private var describer: ScreenDescriber!

    override func setUpWithError() throws {
        try super.setUpWithError()

        guard IntegrationTestHelper.isFakeMirroringRunning else {
            XCTFail(
                "FakeMirroring app is not running. "
                + "Launch it with: open .build/release/FakeMirroring.app"
            )
            return
        }

        bridge = MirroringBridge(bundleID: IntegrationTestHelper.fakeBundleID)
        describer = ScreenDescriber(bridge: bridge, capture: ScreenCapture(bridge: bridge))
    }

    // MARK: - Exploration Session with Real OCR

    func testCaptureAndDedupWithRealOCR() {
        guard let result = describer.describe() else {
            XCTFail("describe() returned nil — cannot test exploration pipeline")
            return
        }

        let session = ExplorationSession()
        session.start(appName: "FakeMirroring", goal: "test dedup")

        // First capture should be accepted
        let first = session.capture(
            elements: result.elements,
            hints: [],
            actionType: nil,
            arrivedVia: nil,
            screenshotBase64: result.screenshotBase64
        )
        XCTAssertTrue(first, "First capture of FakeMirroring screen should be accepted")
        XCTAssertEqual(session.screenCount, 1)

        // Second capture of the same static screen should be rejected (similarity = 1.0)
        guard let result2 = describer.describe() else {
            XCTFail("Second describe() returned nil")
            return
        }

        let second = session.capture(
            elements: result2.elements,
            hints: [],
            actionType: "tap",
            arrivedVia: "Settings",
            screenshotBase64: result2.screenshotBase64
        )
        XCTAssertFalse(second,
            "Recapture of unchanged FakeMirroring screen should be rejected as duplicate")
        XCTAssertEqual(session.screenCount, 1, "Count should stay at 1 after duplicate rejection")
    }

    func testSimilarityScoreWithRealOCR() {
        guard let result = describer.describe() else {
            XCTFail("describe() returned nil")
            return
        }

        // Two OCR passes of the same static screen should have high similarity
        guard let result2 = describer.describe() else {
            XCTFail("Second describe() returned nil")
            return
        }

        let score = ScreenFingerprint.similarity(result.elements, result2.elements)
        XCTAssertGreaterThanOrEqual(score, 0.9,
            "Two OCR passes of the same FakeMirroring screen should have similarity >= 0.9. Got \(score)")
    }

    func testFingerprintExtractProducesStableElements() {
        guard let result = describer.describe() else {
            XCTFail("describe() returned nil")
            return
        }

        let fingerprint = ScreenFingerprint.extract(from: result.elements)

        // FakeMirroring renders: Settings, Safari, Photos, Camera, Messages, Mail, Clock, Maps
        // (9:41 is filtered as a time pattern)
        XCTAssertGreaterThanOrEqual(fingerprint.count, 6,
            "Fingerprint should contain most of FakeMirroring's 8 labels. Got: \(fingerprint)")

        // Verify time pattern is filtered
        let hasTime = fingerprint.contains { $0.contains("9:41") || $0.contains("9:4") }
        XCTAssertFalse(hasTime,
            "Time pattern '9:41' should be filtered from fingerprint. Got: \(fingerprint)")
    }

    // MARK: - End-to-End SKILL.md Generation

    func testGenerateSkillMdFromRealOCR() {
        guard let result = describer.describe() else {
            XCTFail("describe() returned nil")
            return
        }

        let session = ExplorationSession()
        session.start(appName: "FakeMirroring", goal: "verify home screen")

        session.capture(
            elements: result.elements,
            hints: [],
            actionType: nil,
            arrivedVia: nil,
            screenshotBase64: result.screenshotBase64
        )

        guard let data = session.finalize() else {
            XCTFail("finalize() returned nil")
            return
        }

        let skillMd = SkillMdGenerator.generate(
            appName: data.appName,
            goal: data.goal,
            screens: data.screens
        )

        // Front matter
        XCTAssertTrue(skillMd.hasPrefix("---\n"), "Should start with YAML front matter")
        XCTAssertTrue(skillMd.contains("app: FakeMirroring"))
        XCTAssertTrue(skillMd.contains("description: verify home screen"))

        // Launch step
        XCTAssertTrue(skillMd.contains("1. Launch **FakeMirroring**"))

        // Wait-for step: LandmarkPicker should find a landmark from FakeMirroring's labels
        XCTAssertTrue(skillMd.contains("2. Wait for"),
            "Should have a wait-for step from real OCR landmark. Got:\n\(skillMd)")
    }

    func testSetBasedLandmarkDedupWithRealOCR() {
        guard let result = describer.describe() else {
            XCTFail("describe() returned nil")
            return
        }

        // Simulate A-B-A navigation: same screen captured as first and third
        // with a synthetic middle screen
        let screens = [
            ExploredScreen(
                index: 0,
                elements: result.elements,
                hints: [],
                actionType: nil,
                arrivedVia: nil,
                screenshotBase64: result.screenshotBase64
            ),
            ExploredScreen(
                index: 1,
                elements: [
                    TapPoint(text: "About", tapX: 205, tapY: 120, confidence: 0.96),
                    TapPoint(text: "iOS Version 18.2", tapX: 205, tapY: 300, confidence: 0.88),
                ],
                hints: [],
                actionType: "tap",
                arrivedVia: "About",
                screenshotBase64: "synthetic"
            ),
            ExploredScreen(
                index: 2,
                elements: result.elements,
                hints: [],
                actionType: "press_key",
                arrivedVia: "[",
                screenshotBase64: result.screenshotBase64
            ),
        ]

        let skillMd = SkillMdGenerator.generate(
            appName: "FakeMirroring",
            goal: "test landmark dedup",
            screens: screens
        )

        // The landmark from screen 0 should appear only once (Set-based dedup)
        let landmark = LandmarkPicker.pickLandmark(from: result.elements)
        XCTAssertNotNil(landmark, "LandmarkPicker should find a landmark from real OCR")

        if let landmark = landmark {
            let waitLines = skillMd.components(separatedBy: "\n")
                .filter { $0.contains("Wait for \"\(landmark)\" to appear") }
            XCTAssertEqual(waitLines.count, 1,
                "Landmark '\(landmark)' should appear only once despite A-B-A pattern. Got:\n\(skillMd)")
        }
    }
}
