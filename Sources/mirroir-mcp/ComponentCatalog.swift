// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Loads component definitions from the mirroir-skills marketplace repo.
// ABOUTME: Thin wrapper around ComponentLoader for backward compatibility.

import Foundation

/// Loads component definitions from the mirroir-skills marketplace repo.
/// Component definitions live as COMPONENT.md files in `../mirroir-skills/components/ios/`.
enum ComponentCatalog {

    /// All component definitions loaded from the marketplace.
    /// Returns empty array if no COMPONENT.md files are found on disk.
    static var definitions: [ComponentDefinition] {
        ComponentLoader.loadAll()
    }
}
