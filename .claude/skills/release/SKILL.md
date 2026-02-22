---
name: release
description: Release a new version of mirroir-mcp (bump versions, build, test, tag, npm publish, GitHub release, Homebrew formula)
argument-hint: <version>
user-invocable: true
---

# Release mirroir-mcp

Cut a new release. Argument is the version number (e.g. `0.16.0`). Every step must succeed before moving to the next.

## Pre-flight

1. Ensure you are on the `main` branch with a clean working tree:
   ```bash
   git status          # must be clean
   git branch --show-current  # must be "main"
   ```
2. Pull latest:
   ```bash
   git fetch origin && git pull --ff-only origin main
   ```
3. Confirm CI is green on the latest commit:
   ```bash
   gh run list --branch main --limit 3
   ```

## Step 1 — Bump version strings (6 files)

All six files **must** be updated to the new version. No exceptions.

| # | File | What to change |
|---|------|----------------|
| 1 | `npm/package.json` | `"version": "X.Y.Z"` |
| 2 | `npm/install.js` | `const VERSION = "X.Y.Z"` |
| 3 | `server.json` | Both `"version": "X.Y.Z"` fields (top-level and inside `packages[0]`) |
| 4 | `Sources/mirroir-mcp/MCPServer.swift` | `"version": .string("X.Y.Z")` in `handleInitialize` |
| 5 | `Tests/MCPServerTests/MCPServerRoutingTests.swift` | `XCTAssertEqual(serverInfo["version"], .string("X.Y.Z"))` |
| 6 | `../homebrew-tap/Formula/mirroir-mcp.rb` | `url` tag component and will be updated in Step 7 |

**Verify** — grep across ALL file types to make sure no old version remains anywhere:
```bash
grep -rn "OLD_VERSION" --include="*.swift" --include="*.json" --include="*.js" --include="*.md" --include="*.rb" --include="*.sh" --include="*.yml" --include="*.yaml" --include="*.astro" --include="*.css" .
```
If any hit is found, fix it before proceeding. Do NOT skip non-code files — version strings leak into docs, CI, and website.

## Step 2 — Build and test

```bash
swift build
swift test
```

Both must pass. Check that test count > 0 in the output.

## Step 3 — Commit the version bump

```bash
git add npm/package.json npm/install.js server.json \
       Sources/mirroir-mcp/MCPServer.swift \
       Tests/MCPServerTests/MCPServerRoutingTests.swift
git commit -m "chore: bump version to X.Y.Z"
```

## Step 4 — Tag and push

```bash
git tag vX.Y.Z
git push origin main --tags
```

**Wait for CI** — the tag push triggers the `release` job in `build.yml` which creates the GitHub release with tarballs and SHA256SUMS. Monitor:
```bash
gh run list --branch main --limit 3
gh run watch         # watch the triggered run
```

Do NOT proceed until the release job is green and the GitHub release exists.

## Step 5 — Verify GitHub release artifacts

```bash
gh release view vX.Y.Z
```

Confirm it has:
- `mirroir-mcp-darwin-arm64.tar.gz`
- `mirroir-mcp-darwin-x86_64.tar.gz`
- `SHA256SUMS`

## Step 6 — Publish to npm

```bash
cd npm && npm publish --access public
```

npm will prompt for an OTP — ask ChefFamille for it. After publish:
```bash
npm view mirroir-mcp version   # must show X.Y.Z
```

## Step 7 — Update Homebrew formula

1. Download the source tarball and compute SHA256:
   ```bash
   curl -sL "https://github.com/jfarcand/mirroir-mcp/archive/refs/tags/vX.Y.Z.tar.gz" \
     -o /tmp/mirroir-mcp-X.Y.Z.tar.gz
   shasum -a 256 /tmp/mirroir-mcp-X.Y.Z.tar.gz
   ```

2. Update `../homebrew-tap/Formula/mirroir-mcp.rb`:
   - `url` — new tag URL
   - `sha256` — new hash

3. Update `../homebrew-tap/index.md`:
   - Version in the formulae table

4. Commit and push:
   ```bash
   cd ../homebrew-tap
   git add Formula/mirroir-mcp.rb index.md
   git commit -m "feat: mirroir-mcp X.Y.Z"
   git push origin main
   ```

## Step 8 — Verify

Run a final sanity check:
```bash
# npm install works
npx -y mirroir-mcp@X.Y.Z --help

# GitHub release is accessible
gh release view vX.Y.Z --repo jfarcand/mirroir-mcp
```

## Post-release

Clean up the downloaded tarball:
```bash
rm -f /tmp/mirroir-mcp-X.Y.Z.tar.gz
```

Report to ChefFamille:
- npm version published
- GitHub release URL
- Homebrew formula SHA256

## Mistakes to avoid

- **Tag before commit**: always commit version bump first, then tag that commit.
- **Stale versions**: grep for the OLD version across ALL file types after bumping — every hit is a file you missed. Version strings leak into docs, website, CI, and config files.
- **Wrong SHA256**: always compute SHA from the tagged tarball, never from a pre-tag commit.
- **npm from wrong directory**: `npm publish` must run from the `npm/` subdirectory.
- **Skipping tests**: never tag without `swift build && swift test` passing.
- **Homebrew tap forgotten**: the formula, index.md version, and SHA256 all need updating.
- **Narrow grep**: do NOT limit version grep to just `.swift`/`.json`/`.js` — include `.md`, `.rb`, `.yml`, `.yaml`, `.astro`, `.css`, `.sh` too.
