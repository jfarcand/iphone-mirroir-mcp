---
name: release
description: Release a new version of mirroir-mcp (bump versions, build, test, tag, npm publish, GitHub release, Homebrew formula)
argument-hint: <version>
user-invocable: true
---

# Release mirroir-mcp

Cut a new release. Argument is the version number (e.g. `0.22.0`).

Releases are automated via the `release.yml` GitHub Actions workflow. This skill triggers the workflow and monitors progress.

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

## Step 1 — Trigger the release workflow

```bash
gh workflow run release.yml -f version=X.Y.Z
```

## Step 2 — Monitor progress

```bash
gh run list --workflow=release.yml --limit 1
gh run watch    # watch the triggered run
```

The workflow runs 4 jobs:

| Job | What it does |
|-----|-------------|
| `release` | Bumps 5 version files, builds, tests, commits, tags, creates GitHub release with tarball + SHA256SUMS |
| `update-homebrew` | Updates `Formula/mirroir-mcp.rb` (url + sha256) and `index.md` in `jfarcand/homebrew-tap` |
| `update-skills` | Bumps version in `marketplace.json` files in `jfarcand/mirroir-scenarios` |
| `publish-npm` | Publishes to npm and verifies |

## Step 3 — Verify

After all 4 jobs are green:

```bash
# GitHub release
gh release view vX.Y.Z --repo jfarcand/mirroir-mcp

# npm
npm view mirroir-mcp version   # must show X.Y.Z

# npx install works
npx -y mirroir-mcp@X.Y.Z --help
```

Report to ChefFamille:
- GitHub release URL
- npm version published
- All 4 jobs green

## Version files bumped by the workflow

| # | File | What changes |
|---|------|-------------|
| 1 | `npm/package.json` | `"version": "X.Y.Z"` |
| 2 | `npm/install.js` | `const VERSION = "X.Y.Z"` |
| 3 | `server.json` | Both `"version": "X.Y.Z"` fields |
| 4 | `Sources/mirroir-mcp/MCPServer.swift` | `"version": .string("X.Y.Z")` |
| 5 | `Tests/MCPServerTests/MCPServerRoutingTests.swift` | Version assertion |
| 6 | `../homebrew-tap/Formula/mirroir-mcp.rb` | `url` + `sha256` |
| 7 | `../homebrew-tap/index.md` | Version in formulae table |
| 8 | `mirroir-scenarios/.claude-plugin/marketplace.json` | `"version"` fields |
| 9 | `mirroir-scenarios/.github/plugin/marketplace.json` | `"version"` fields |

## Required secrets

| Secret | Purpose |
|--------|---------|
| `RELEASE_PAT` | GitHub PAT with `repo` scope — pushes to homebrew-tap + mirroir-scenarios |
| `NPM_TOKEN` | npm automation token — publishes without OTP |
| `GITHUB_TOKEN` | Built-in — pushes to own repo + creates GitHub release |

## Manual fallback

If the workflow fails partway through, check which job failed and either re-run from the failed job or fix and re-trigger. The `release` job is idempotent-safe: it checks for duplicate tags and matching versions before proceeding.

## Mistakes to avoid

- **Triggering with wrong version format**: must be `X.Y.Z` (no `v` prefix).
- **Missing secrets**: both `RELEASE_PAT` and `NPM_TOKEN` must be set in repo settings before first run.
- **Dirty working tree**: push all changes before triggering — the workflow checks out `main` HEAD.
- **Re-running after partial success**: if the `release` job succeeded (tag exists), downstream jobs can be re-run individually.
