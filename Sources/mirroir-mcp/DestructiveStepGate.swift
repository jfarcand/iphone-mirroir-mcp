// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Refuses a skill run containing unconfirmed steps that act on the real world.
// ABOUTME: Combines built-in confirm patterns with permissions.json and reports what it blocked.

import Foundation
import HelperLib

/// Decides whether a run may proceed, given the steps it is about to execute.
///
/// Separated from `TestRunner` so the policy — which steps need a say-so, and
/// what the user is told about them — is readable on its own.
enum DestructiveStepGate {

    /// Refuse a run whose skills contain steps with real-world consequences,
    /// unless the caller confirmed them.
    ///
    /// The whole set of skills is checked before any step executes. Blocking
    /// midway would leave the device half-finished, which is worse than never
    /// starting: the caller would have to work out which effects already
    /// happened. Returns the exit code to return, or `nil` to proceed.
    static func refuse(
        skills: [SkillDefinition], dryRun: Bool, confirmed: Bool
    ) -> Int32? {
        // A dry run executes nothing, so there is nothing to confirm.
        guard !dryRun, !confirmed else { return nil }

        let matches = DestructiveStepDetector.scan(skills: skills, patterns: activePatterns())
        guard !matches.isEmpty else { return nil }

        report(matches)
        return 1
    }

    /// Built-in safety patterns plus any the user added in permissions.json.
    ///
    /// Config patterns extend the built-ins and never replace them — a user
    /// narrowing the list would be silently removing a safety guard.
    static func activePatterns() -> [String] {
        DestructiveStepDetector.builtInConfirmPatterns
            + (PermissionPolicy.loadConfig()?.confirmElements ?? [])
    }

    /// Tell the user exactly what was blocked and how to proceed.
    private static func report(_ matches: [DestructiveStepDetector.Match]) {
        fputs("Refusing to run: \(matches.count) step(s) act on the real world.\n\n", stderr)
        for match in matches {
            fputs("  \(match.skillName) step \(match.stepNumber): "
                + "\(match.summary)  [\(match.reason)]\n", stderr)
        }
        fputs("\nThese send, remove, spend, or reset something on a live device and "
            + "cannot be undone by re-running.\n"
            + "Preview them with --dry-run, or execute them with --confirm-destructive.\n",
            stderr)
    }
}
