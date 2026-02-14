# Copilot Instructions for HueBar

## Project Overview
HueBar is a native macOS menubar app (SwiftUI, macOS 15+) for controlling Philips Hue lights via the Hue CLIP API v2. It uses `MenuBarExtra` with `.window` style for the popover UI.

## Tech Stack
- **Language**: Swift 6 with strict concurrency
- **UI**: SwiftUI (`MenuBarExtra`, `@Observable`)
- **Networking**: URLSession with custom TLS delegate for Hue Bridge self-signed certs
- **Discovery**: NWBrowser (mDNS) + cloud fallback (discovery.meethue.com)
- **Storage**: Credentials file in `~/Library/Application Support/HueBar/` (600 permissions)
- **Dependencies**: None external — Apple frameworks only

## Key Patterns
- `@Observable` + `@MainActor` for all stateful service classes
- `HueResponse<T>` generic envelope for decoding Hue API v2 responses (`{"errors":[],"data":[...]}`)
- Optimistic UI updates for toggles (update local state before API call, revert on failure)
- `Sendable` compliance throughout for Swift 6 strict concurrency

## Accent Color / Tint
- **Never** use a global `.tint()` modifier on the view hierarchy — it forces the accent color onto every interactive element (buttons, text links, etc.) making them hard to read
- Instead, apply `.tint(.hueAccent)` only to specific controls that should be accented: light toggles and brightness sliders
- `Color.hueAccent` is defined in `ColorConversion.swift`
- Buttons and navigation text should use default (`.primary`) styling

## Hue API v2 (CLIP)
- Base URL: `https://<bridge_ip>/clip/v2/resource/`
- Auth: `hue-application-key` header
- Key resources: `room`, `zone`, `grouped_light`
- Toggle: PUT to `grouped_light/<id>` with `{"on":{"on":true/false}}`
- The bridge uses a self-signed HTTPS certificate — `HueBridgeTrustDelegate` handles this

## Build & Run
```bash
swift build        # build
swift run          # run
swift build -c release  # release build
```
