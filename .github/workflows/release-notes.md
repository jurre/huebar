---
description: Generates user-friendly release notes when a new release is published
on:
  release:
    types: [published]
permissions:
  contents: read
  pull-requests: read
tools:
  github:
    toolsets: [pull_requests, repos]
safe-outputs:
  update-release:
timeout-minutes: 10
---

# HueBar Release Notes Generator

Generate clear, user-friendly release notes for HueBar, a macOS menubar app for controlling Philips Hue lights.

## Context

- **Repository**: ${{ github.repository }}
- **Release Tag**: ${{ github.event.release.tag_name }}

## Step 1: Gather Data

Use bash and GitHub tools to collect information:

```bash
# Get the current release body (auto-generated notes)
gh release view "${{ github.event.release.tag_name }}" --json body --jq .body > /tmp/release_body.txt

# Get the previous release tag
PREV_TAG=$(gh release list --limit 2 --json tagName --jq '.[1].tagName // empty')
echo "Previous: $PREV_TAG"

# List PRs merged between releases
if [ -n "$PREV_TAG" ]; then
  PREV_DATE=$(gh release view "$PREV_TAG" --json publishedAt --jq .publishedAt)
  CURR_DATE=$(gh release view "${{ github.event.release.tag_name }}" --json publishedAt --jq .publishedAt)
  gh pr list --state merged --limit 100 \
    --json number,title,labels,mergedAt \
    --jq "[.[] | select(.mergedAt >= \"$PREV_DATE\" and .mergedAt <= \"$CURR_DATE\")]"
fi
```

## Step 2: Categorize Changes

Group changes into these categories (omit empty ones):

- **✨ New Features** — User-visible new capabilities
- **🐛 Bug Fixes** — Issues resolved
- **⚡ Improvements** — Performance, reliability, code quality
- **📚 Documentation** — AGENTS.md or README updates

Skip purely internal refactoring unless it improves user experience.

## Step 3: Write Release Notes

Format:

```markdown
## What's New in [tag]

[1 sentence summary]

### ✨ New Features
- Feature description (#PR)

### 🐛 Bug Fixes
- Fix description (#PR)

### ⚡ Improvements
- Improvement description (#PR)
```

**Writing guidelines:**
- Lead with user benefit: "Lights now respond faster" not "Reduced API latency"
- Keep it scannable — one line per change
- Link PR numbers
- Skip developer-only changes

## Step 4: Update Release

Call the `update_release` safe output to prepend the highlights before the auto-generated notes:

- `tag`: "${{ github.event.release.tag_name }}"
- `operation`: "prepend"
- `body`: Your formatted release notes markdown
