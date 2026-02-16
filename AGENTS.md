# Instructions for HueBar

## Project Overview
HueBar is a native macOS menubar app (SwiftUI, macOS 15+) for controlling Philips Hue lights via the Hue CLIP API v2. It uses `MenuBarExtra` with `.window` style for the popover UI. Supports multiple Hue Bridges.

## Tech Stack
- **Language**: Swift 6 with strict concurrency
- **UI**: SwiftUI (`MenuBarExtra`, `@Observable`)
- **Networking**: URLSession with custom TLS delegate for Hue Bridge self-signed certs
- **Discovery**: NWBrowser (mDNS) + cloud fallback (discovery.meethue.com)
- **Storage**: Credentials file in `~/Library/Application Support/HueBar/` (600 permissions)
- **Dependencies**: None external — Apple frameworks only

## Architecture

### Multi-bridge
HueBar supports multiple Hue Bridges. `BridgeManager` holds an array of `BridgeConnection`, each wrapping its own `HueAPIClient`. Features that enumerate rooms/zones (hotkeys, sleep/wake, pickers) must iterate **all bridges**, not just the first.

### Key Patterns
- `@Observable` + `@MainActor` for all stateful service classes
- `HueResponse<T>` generic envelope for decoding Hue API v2 responses (`{"errors":[],"data":[...]}`)
- Optimistic UI updates for toggles (update local state before API call, revert on failure)
- `Sendable` compliance throughout for Swift 6 strict concurrency

### Error Handling
- Never use `try?` silently — always wrap in `do/catch` and log errors with `os.Logger`
- Use `Logger(subsystem: "com.huebar", category: "<ClassName>")` for each class
- Exception: `try? await Task.sleep(...)` is fine since cancellation is expected, not an error
- Users rely on automations (hotkeys, sleep/wake) working invisibly — if they fail silently, the user has no way to diagnose why

### Concurrency Safety
- When using `nonisolated(unsafe)`, always add a `// SAFETY:` comment explaining why it's safe
- Document the threading model: which thread accesses the value and when
- For C callback interop (e.g., Carbon hotkeys), explain that callbacks run on the main thread

### Model Mutability
- Use `var` for model properties that are updated optimistically (e.g., `on`, `dimming`, `color`, `colorTemperature`, `status`, `speed`)
- Never reconstruct entire structs just to change one field — use direct property mutation: `lights[index].on = OnState(on: on)`
- Keep `let` for identity/metadata fields that never change after creation (e.g., `id`, `owner`, `metadata`)

### Type Safety
- Use enums over raw strings for dispatch/selection patterns (e.g., `PinCategory` instead of string keys)
- Avoid `default` branches in switch statements when all cases should be explicitly handled
- Prefer `guard let` over force-unwraps (`!`) even when the value is known to be non-nil from context

### Event Stream
- Debounce bulk add/delete events before triggering `fetchAll()` — bursts of events should coalesce into a single refresh
- Use `refreshDebounceTask` pattern: cancel previous, sleep briefly, check cancellation, then fetch

### Network addresses
Bridge IPs can be IPv4, IPv6, or include a port (for mock bridges). **Never split on `":"` to parse host/port** — this breaks IPv6 addresses. Always use `IPValidation.parseHostPort()` which handles all formats (IPv4, IPv4:port, bare IPv6, `[IPv6]:port`).

### App lifecycle
`HueBarApp.init()` runs before views are created. Any feature that needs to work on app launch (hotkeys, sleep/wake, bridge connections) must be configured there, not only in view `.task` modifiers or setup completion handlers.

## Accent Color / Tint
- **Never** use a global `.tint()` modifier on the view hierarchy — it forces the accent color onto every interactive element (buttons, text links, etc.) making them hard to read
- Instead, apply `.tint(.hueAccent)` only to specific controls that should be accented: light toggles and brightness sliders
- `Color.hueAccent` is defined in `ColorConversion.swift`
- Buttons and navigation text should use default (`.primary`) styling

## Accessibility
- **Every** interactive control (buttons, sliders, toggles) must have an `.accessibilityLabel()`
- Sliders should also have a separate `.accessibilityValue()` so VoiceOver can announce dynamic values
- Do not embed changing values in the label — use `.accessibilityValue()` instead
- Custom controls (e.g. `ColorTemperatureSlider`) must manually add accessibility modifiers since they don't inherit them from native SwiftUI controls

## Known Platform Limitations

### Drag-and-Drop in MenuBarExtra
Drag-and-drop is **completely broken** in `MenuBarExtra` (`.window` style) panels. The `NSPanel` used by MenuBarExtra does not dispatch `NSDraggingDestination` events (`draggingEntered`, `draggingUpdated`, `performDragOperation`) to subviews. This was confirmed across five different approaches in Feb 2025:

1. **SwiftUI `.dropDestination(for:)`** — drop targets never activate
2. **SwiftUI `.onDrop` with `DropDelegate`** — `dropEntered`/`performDrop` never called
3. **AppKit `registerForDraggedTypes` + `NSDraggingDestination`** on `NSViewRepresentable` overlays — `draggingEntered` never called, even with `hitTest: nil` and ancestor view unregistration
4. **AppKit `beginDraggingSession`** for drag source + AppKit destinations — drag source works (outline visible) but destination events still never fire
5. **Custom mouse-tracking** bypassing all drag-and-drop APIs — functional but felt unnatural; overlay NSView intercepting all events is fragile (caused infinite recursion crashes in event forwarding)

**Current solution:** Context menu reordering (Move Up/Down/Top/Bottom) via `RoomOrderManager`. Custom order is persisted in UserDefaults.

**If revisiting:** The root issue is the `NSPanel` window type. If Apple changes `MenuBarExtra` to use a different window type, or fixes drag event dispatch in panels, standard SwiftUI drag-and-drop (approach 1 or 2) would be the cleanest solution. Test with a simple `.draggable()` + `.dropDestination()` first before investing in workarounds.

## UI Feedback Loops
- SwiftUI `onChange` fires for BOTH user input AND programmatic updates — always guard against feedback loops
- For sliders: use `onEditingChanged` to track `isUserDragging` state
- Only send API requests when `isUserDragging == true`; only sync from API state when `isUserDragging == false`
- Check all slider-like controls: brightness, speed, color temperature

## Security Framework APIs
- Always check return values of Security framework functions (`SecTrust*`, etc.)
- Use fail-closed behavior: if a security API call fails, cancel/reject the operation
- Match existing patterns in `TrustDelegate.swift` — `guard status == errSecSuccess else { return (.cancelAuthenticationChallenge, nil) }`

## Hue API v2 (CLIP)
- Base URL: `https://<bridge_ip>/clip/v2/resource/`
- Auth: `hue-application-key` header
- Key resources: `room`, `zone`, `grouped_light`
- Toggle: PUT to `grouped_light/<id>` with `{"on":{"on":true/false}}`
- The bridge uses a self-signed HTTPS certificate — `HueBridgeTrustDelegate` handles this

## Build & Run
```bash
swift build                        # build
swift test                         # run tests
swift run                          # run app
swift build -c release             # release build
./scripts/install.sh               # build + install to /Applications
./scripts/mock-bridges.sh          # start mock bridges for UI testing
```
