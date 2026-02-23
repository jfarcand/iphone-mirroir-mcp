// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Unit tests for StrategyDetector: auto-detection of exploration strategy from target metadata.
// ABOUTME: Covers explicit override, target type, bundle ID, app name matching, and default fallback.

import XCTest
@testable import mirroir_mcp

final class StrategyDetectorTests: XCTestCase {

    // MARK: - Explicit Override

    func testExplicitOverrideMobile() {
        let result = StrategyDetector.detect(
            targetType: "generic-window", bundleID: nil,
            appName: "Reddit", explicitStrategy: "mobile")
        XCTAssertEqual(result, .mobile,
            "Explicit 'mobile' should override all other signals")
    }

    func testExplicitOverrideSocial() {
        let result = StrategyDetector.detect(
            targetType: "iphone-mirroring", bundleID: nil,
            appName: "Settings", explicitStrategy: "social")
        XCTAssertEqual(result, .social)
    }

    func testExplicitOverrideDesktop() {
        let result = StrategyDetector.detect(
            targetType: "iphone-mirroring", bundleID: nil,
            appName: "Settings", explicitStrategy: "desktop")
        XCTAssertEqual(result, .desktop)
    }

    func testInvalidExplicitOverrideFallsThrough() {
        let result = StrategyDetector.detect(
            targetType: "iphone-mirroring", bundleID: nil,
            appName: "Settings", explicitStrategy: "invalid")
        XCTAssertEqual(result, .mobile,
            "Invalid explicit strategy should fall through to default detection")
    }

    // MARK: - Target Type Detection

    func testGenericWindowDetectsDesktop() {
        let result = StrategyDetector.detect(
            targetType: "generic-window", bundleID: nil,
            appName: "Finder")
        XCTAssertEqual(result, .desktop)
    }

    func testIPhoneMirroringDefaultsMobile() {
        let result = StrategyDetector.detect(
            targetType: "iphone-mirroring", bundleID: nil,
            appName: "Settings")
        XCTAssertEqual(result, .mobile)
    }

    // MARK: - Bundle ID Detection

    func testRedditBundleIDDetectsSocial() {
        let result = StrategyDetector.detect(
            targetType: "iphone-mirroring",
            bundleID: "com.reddit.Reddit",
            appName: "SomeApp")
        XCTAssertEqual(result, .social)
    }

    func testInstagramBundleIDDetectsSocial() {
        let result = StrategyDetector.detect(
            targetType: "iphone-mirroring",
            bundleID: "com.instagram.Instagram",
            appName: "SomeApp")
        XCTAssertEqual(result, .social)
    }

    func testTwitterBundleIDDetectsSocial() {
        let result = StrategyDetector.detect(
            targetType: "iphone-mirroring",
            bundleID: "com.atebits.Tweetie2",
            appName: "SomeApp")
        XCTAssertEqual(result, .social)
    }

    func testUnknownBundleIDFallsToAppName() {
        let result = StrategyDetector.detect(
            targetType: "iphone-mirroring",
            bundleID: "com.example.MyApp",
            appName: "Reddit")
        XCTAssertEqual(result, .social,
            "Unknown bundle ID should fall through to app name check")
    }

    // MARK: - App Name Detection

    func testRedditAppNameDetectsSocial() {
        let result = StrategyDetector.detect(
            targetType: "iphone-mirroring", bundleID: nil,
            appName: "Reddit")
        XCTAssertEqual(result, .social)
    }

    func testTikTokAppNameDetectsSocial() {
        let result = StrategyDetector.detect(
            targetType: "iphone-mirroring", bundleID: nil,
            appName: "TikTok")
        XCTAssertEqual(result, .social)
    }

    func testAppNameIsCaseInsensitive() {
        let result = StrategyDetector.detect(
            targetType: "iphone-mirroring", bundleID: nil,
            appName: "INSTAGRAM")
        XCTAssertEqual(result, .social)
    }

    // MARK: - Default Fallback

    func testUnknownAppDefaultsToMobile() {
        let result = StrategyDetector.detect(
            targetType: "iphone-mirroring", bundleID: nil,
            appName: "Calculator")
        XCTAssertEqual(result, .mobile)
    }
}
