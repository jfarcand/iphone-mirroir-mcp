// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Tests for SpotlightDetector: verifying Spotlight overlay detection from OCR elements.
// ABOUTME: Covers English, French indicators and false-positive rejection for normal app screens.

import XCTest
@testable import mirroir_mcp
@testable import HelperLib

final class SpotlightDetectorTests: XCTestCase {

    // MARK: - Spotlight Detection

    func testDetectsEnglishSpotlight() {
        let elements = [
            TapPoint(text: "Settings", tapX: 200, tapY: 100, confidence: 0.9),
            TapPoint(text: "Top Hit", tapX: 200, tapY: 200, confidence: 0.9),
            TapPoint(text: "Search in App", tapX: 200, tapY: 300, confidence: 0.9),
        ]

        XCTAssertTrue(SpotlightDetector.isSpotlightVisible(elements: elements))
    }

    func testDetectsFrenchSpotlight() {
        let elements = [
            TapPoint(text: "Réglages", tapX: 200, tapY: 100, confidence: 0.9),
            TapPoint(text: "Meilleur résultat", tapX: 200, tapY: 200, confidence: 0.9),
            TapPoint(text: "Rechercher dans l'app", tapX: 200, tapY: 300, confidence: 0.9),
        ]

        XCTAssertTrue(SpotlightDetector.isSpotlightVisible(elements: elements))
    }

    func testDetectsSpanishSpotlight() {
        let elements = [
            TapPoint(text: "Ajustes", tapX: 200, tapY: 100, confidence: 0.9),
            TapPoint(text: "Sugerencias de Siri", tapX: 200, tapY: 200, confidence: 0.9),
        ]

        XCTAssertTrue(SpotlightDetector.isSpotlightVisible(elements: elements))
    }

    func testDetectsGermanSpotlight() {
        let elements = [
            TapPoint(text: "Einstellungen", tapX: 200, tapY: 100, confidence: 0.9),
            TapPoint(text: "Siri-Vorschläge", tapX: 200, tapY: 200, confidence: 0.9),
        ]

        XCTAssertTrue(SpotlightDetector.isSpotlightVisible(elements: elements))
    }

    func testIsCaseInsensitive() {
        let elements = [
            TapPoint(text: "top hit", tapX: 200, tapY: 200, confidence: 0.9),
        ]

        XCTAssertTrue(SpotlightDetector.isSpotlightVisible(elements: elements))
    }

    // MARK: - Normal App Screens (False Positive Rejection)

    func testSettingsRootNotDetectedAsSpotlight() {
        let elements = [
            TapPoint(text: "Réglages", tapX: 100, tapY: 179, confidence: 0.9),
            TapPoint(text: "Jeanfrancois Arcand", tapX: 207, tapY: 240, confidence: 0.9),
            TapPoint(text: "Wi-Fi", tapX: 104, tapY: 556, confidence: 0.9),
            TapPoint(text: "Bluetooth", tapX: 120, tapY: 609, confidence: 0.9),
            TapPoint(text: "Batterie", tapX: 110, tapY: 767, confidence: 0.9),
        ]

        XCTAssertFalse(SpotlightDetector.isSpotlightVisible(elements: elements))
    }

    func testSlackHomeNotDetectedAsSpotlight() {
        let elements = [
            TapPoint(text: "Home", tapX: 115, tapY: 727, confidence: 0.9),
            TapPoint(text: "DMs", tapX: 162, tapY: 728, confidence: 0.9),
            TapPoint(text: "Activity", tapX: 208, tapY: 728, confidence: 0.9),
            TapPoint(text: "More", tapX: 255, tapY: 728, confidence: 0.9),
        ]

        XCTAssertFalse(SpotlightDetector.isSpotlightVisible(elements: elements))
    }

    func testEmptyElementsNotDetectedAsSpotlight() {
        XCTAssertFalse(SpotlightDetector.isSpotlightVisible(elements: []))
    }

    // MARK: - Partial Indicator Match

    func testDetectsPartialIndicatorInText() {
        // "Siri Suggestions" contained within a longer element text
        let elements = [
            TapPoint(text: "Show Siri Suggestions on Lock Screen", tapX: 200, tapY: 300, confidence: 0.9),
        ]

        XCTAssertTrue(SpotlightDetector.isSpotlightVisible(elements: elements))
    }
}
