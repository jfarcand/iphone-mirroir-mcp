// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Generates multiple SKILL.md files from a GraphSnapshot by finding interesting paths.
// ABOUTME: Wraps SkillMdGenerator to produce one skill per distinct flow through the app.

import Foundation
import HelperLib

/// A bundle of SKILL.md files produced from a single exploration session.
struct SkillBundle: Sendable {
    /// The app that was explored.
    let appName: String
    /// Individual skills, each representing a distinct flow.
    let skills: [(name: String, content: String)]
}

/// Generates a bundle of SKILL.md files from a graph snapshot.
/// Each interesting path through the graph becomes a separate skill.
enum SkillBundleGenerator {

    /// Generate a skill bundle from a graph snapshot.
    /// Falls back to a single skill from the full screen list when the graph
    /// has only one path or no interesting paths.
    ///
    /// - Parameters:
    ///   - appName: The app that was explored.
    ///   - goal: Optional goal description.
    ///   - snapshot: The navigation graph snapshot.
    ///   - allScreens: Complete flat list of screens (fallback for single-path graphs).
    /// - Returns: A SkillBundle with one or more skills.
    static func generate(
        appName: String,
        goal: String,
        snapshot: GraphSnapshot,
        allScreens: [ExploredScreen]
    ) -> SkillBundle {
        let paths = GraphPathFinder.findInterestingPaths(in: snapshot)

        // If fewer than 2 interesting paths, generate a single skill from the flat list
        guard paths.count >= 2 else {
            let content = SkillMdGenerator.generate(
                appName: appName, goal: goal, screens: allScreens
            )
            let name = SkillMdGenerator.deriveName(appName: appName, goal: goal)
            return SkillBundle(appName: appName, skills: [(name: name, content: content)])
        }

        // Generate one skill per interesting path
        var skills: [(name: String, content: String)] = []
        for path in paths {
            let screens = GraphPathFinder.pathToExploredScreens(
                path: path.edges, snapshot: snapshot
            )
            guard !screens.isEmpty else { continue }

            let pathGoal = path.name
            let content = SkillMdGenerator.generate(
                appName: appName, goal: pathGoal, screens: screens
            )
            let name = SkillMdGenerator.deriveName(appName: appName, goal: pathGoal)
            skills.append((name: name, content: content))
        }

        // Fallback if all paths produced empty screen lists
        if skills.isEmpty {
            let content = SkillMdGenerator.generate(
                appName: appName, goal: goal, screens: allScreens
            )
            let name = SkillMdGenerator.deriveName(appName: appName, goal: goal)
            return SkillBundle(appName: appName, skills: [(name: name, content: content)])
        }

        return SkillBundle(appName: appName, skills: skills)
    }
}
