# HueBar

A native macOS menubar app for controlling your Philips Hue lights. See your rooms and zones at a glance and toggle them on and off — right from the menu bar.

<img width="300" alt="HueBar screenshot" src="https://github.com/user-attachments/assets/3bc9646a-a02e-44a6-92db-e98d3a93d1dc">

## Features

- 💡 **Rooms & Zones** — View all your Hue rooms and zones with on/off toggles
- 🔍 **Auto-discovery** — Finds your Hue Bridge automatically via mDNS and cloud discovery
- 🔒 **Secure** — Application key stored in the macOS Keychain
- 🪶 **Lightweight** — Native SwiftUI, no external dependencies, lives in your menu bar

## Requirements

- macOS 15.0 (Sequoia) or later
- A Philips Hue Bridge on your local network

## Installation

### Install as app (recommended)

```bash
git clone https://github.com/jurre/huebar.git
cd huebar
./scripts/install.sh
```

This builds a release binary, wraps it in a `.app` bundle, code-signs it, and copies it to `/Applications`. You can then launch HueBar from Spotlight or Finder.

To start automatically on login, toggle **"Launch at Login"** in the HueBar menu.

### Run from source

```bash
swift run
```

## Setup

1. Launch HueBar — a lightbulb icon appears in your menu bar
2. The app will search for your Hue Bridge on the network
3. When your bridge is found, click it and press the **link button** on your physical Hue Bridge
4. That's it — your rooms and zones appear with toggle switches

## Architecture

HueBar uses the [Hue CLIP API v2](https://developers.meethue.com/develop/hue-api-v2/) for modern resource-based control. No external dependencies — only Apple frameworks:

- **SwiftUI** — `MenuBarExtra` with `.window` style for the popover UI
- **Network** — `NWBrowser` for mDNS bridge discovery
- **Foundation** — `URLSession` for HTTPS communication

```
Sources/HueBar/
├── HueBarApp.swift              # App entry point, MenuBarExtra
├── Views/
│   ├── MenuBarView.swift        # Room/zone list with toggles
│   └── SetupView.swift          # Bridge discovery & auth flow
├── Models/
│   ├── Room.swift               # Room model + API response types
│   ├── Zone.swift               # Zone model
│   └── GroupedLight.swift       # Grouped light state (on/off, brightness)
├── Services/
│   ├── HueBridgeDiscovery.swift # mDNS + cloud bridge discovery
│   ├── HueAPIClient.swift       # CLIP v2 API client
│   ├── HueAuthService.swift     # Link-button authentication
│   └── CredentialStore.swift    # Credential storage (~/.../Application Support)
└── Utilities/
    └── TrustDelegate.swift      # Self-signed cert handling
```

## License

[MIT](LICENSE)
