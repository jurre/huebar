# Contributing to HueBar

Thanks for your interest in contributing! HueBar is a small project and contributions of all sizes are welcome.

## Getting Started

1. Fork and clone the repo
2. Build: `swift build`
3. Run: `swift run`
4. Run tests: `swift test`

Requires macOS 15 (Sequoia) and Xcode 16+.

## Making Changes

- Create a branch from `main`
- Keep changes focused — one feature or fix per PR
- Follow existing code style: `@Observable` + `@MainActor` for service classes, Swift 6 strict concurrency
- Add tests where practical

## Submitting a Pull Request

1. Push your branch and open a PR against `main`
2. Describe what you changed and why
3. If it's a UI change, include a screenshot

## Releases

Releases are automatically created when changes are pushed to `main` that modify source code, resources, or package dependencies. The release workflow:

1. Generates a version tag based on the current date and commit SHA (e.g., `v2026.02.14-abc1234`)
2. Builds a release binary with `swift build -c release`
3. Creates a signed `.app` bundle and packages it as `HueBar.zip`
4. Generates release notes from commits since the last release
5. Publishes a GitHub release with the version tag and binary asset

To manually trigger a release, push a commit that changes files in:
- `Sources/**`
- `Resources/**`
- `Package.swift`
- `Package.resolved`

The workflow will skip creating a release if the generated version tag already exists.

## Reporting Issues

Found a bug or have a feature idea? [Open an issue](https://github.com/jurre/huebar/issues/new). Include steps to reproduce for bugs, or a clear description for feature requests.

## Code of Conduct

Be kind and constructive. We're all here to make a nice little app.
