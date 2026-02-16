import SwiftUI
import UniformTypeIdentifiers

struct MenuBarView: View {
    @Bindable var bridgeManager: BridgeManager
    @Bindable var hotkeyManager: HotkeyManager
    @Bindable var sleepWakeManager: SleepWakeManager
    var onSignOut: () -> Void

    @State private var selectedRoom: Room?
    @State private var selectedZone: Zone?
    @State private var selectedClient: HueAPIClient?
    @State private var showSettings = false
    
    // Drag-and-drop state: track the ID being dragged and which target is hovered
    @State private var draggingRoomId: String?
    @State private var draggingZoneId: String?
    @State private var roomDragTarget: String?
    @State private var zoneDragTarget: String?
    
    // Visual styling for drag targets
    private let dragTargetHighlight = Color.blue.opacity(0.2)

    /// The primary bridge client (first connected bridge)
    private var primaryClient: HueAPIClient? {
        bridgeManager.bridges.first?.client
    }

    /// Whether to show multi-bridge section headers
    private var hasMultipleBridges: Bool {
        bridgeManager.bridges.count > 1
    }

    var body: some View {
        VStack(spacing: 0) {
            if showSettings {
                SettingsView(
                    bridgeManager: bridgeManager,
                    hotkeyManager: hotkeyManager,
                    sleepWakeManager: sleepWakeManager,
                    onSignOut: onSignOut,
                    onBack: { withAnimation(.easeInOut(duration: 0.25)) { showSettings = false } }
                )
                .transition(.move(edge: .trailing))
            } else if let room = selectedRoom, let client = selectedClient ?? primaryClient {
                RoomDetailView(
                    apiClient: client,
                    target: .room(room),
                    onBack: { withAnimation(.easeInOut(duration: 0.25)) { selectedRoom = nil; selectedClient = nil } }
                )
                .transition(.move(edge: .trailing))
            } else if let zone = selectedZone, let client = selectedClient ?? primaryClient {
                RoomDetailView(
                    apiClient: client,
                    target: .zone(zone),
                    onBack: { withAnimation(.easeInOut(duration: 0.25)) { selectedZone = nil; selectedClient = nil } }
                )
                .transition(.move(edge: .trailing))
            } else {
                roomListView
                    .transition(.move(edge: .leading))
            }
        }
        .frame(width: 300, height: 550)
        .clipped()
        .preferredColorScheme(.dark)
    }

    // MARK: - Room List

    private var roomListView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("HueBar")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { showSettings = true }
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            // Content
            if hasMultipleBridges {
                multiBridgeContent
            } else {
                singleBridgeContent
            }
        }
    }

    // MARK: - Multi-Bridge Content

    @ViewBuilder
    private var multiBridgeContent: some View {
        if bridgeManager.isLoading && bridgeManager.bridges.allSatisfy({ $0.client.rooms.isEmpty && $0.client.zones.isEmpty }) {
            Spacer()
            ProgressView("Loading…")
            Spacer()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(bridgeManager.bridges) { bridge in
                        bridgeSection(bridge)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func bridgeSection(_ bridge: BridgeConnection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(bridge.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal)
                .padding(.top, 8)

            switch bridge.status {
            case .disconnected, .connecting:
                ProgressView()
                    .padding(.horizontal)
            case .error(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            case .connected:
                if !bridge.client.rooms.isEmpty {
                    sectionHeader("Rooms", icon: "house")
                    ForEach(bridge.client.rooms) { room in
                        LightRowView(apiClient: bridge.client, name: room.name, archetype: room.metadata.archetype, groupedLightId: room.groupedLightId, groupId: room.id, isPinned: bridge.client.isRoomPinned(room.id)) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                selectedClient = bridge.client
                                selectedRoom = room
                            }
                        }
                        .background(roomDragTarget == room.id ? dragTargetHighlight : Color.clear)
                        .onDrag {
                            draggingRoomId = room.id
                            return NSItemProvider(object: room.id as NSString)
                        }
                        .onDrop(of: [.text], delegate: ReorderDropDelegate(
                            targetId: room.id,
                            draggingId: $draggingRoomId,
                            dragTarget: $roomDragTarget,
                            onMove: { fromId, toId in bridge.client.moveRoom(fromId: fromId, toId: toId) }
                        ))
                        .contextMenu {
                            Button(bridge.client.isRoomPinned(room.id) ? "Unpin" : "Pin to Top") {
                                withAnimation { bridge.client.toggleRoomPin(room.id) }
                            }
                            if let idx = bridge.client.rooms.firstIndex(where: { $0.id == room.id }), idx > 0 {
                                Button("Move Up") {
                                    bridge.client.moveRoom(fromId: room.id, toId: bridge.client.rooms[idx - 1].id)
                                }
                            }
                            if let idx = bridge.client.rooms.firstIndex(where: { $0.id == room.id }), idx < bridge.client.rooms.count - 1 {
                                Button("Move Down") {
                                    bridge.client.moveRoom(fromId: room.id, toId: bridge.client.rooms[idx + 1].id)
                                }
                            }
                        }
                    }
                }

                if !bridge.client.zones.isEmpty {
                    sectionHeader("Zones", icon: "square.grid.2x2")
                    ForEach(bridge.client.zones) { zone in
                        LightRowView(apiClient: bridge.client, name: zone.name, archetype: zone.metadata.archetype, groupedLightId: zone.groupedLightId, groupId: zone.id, isPinned: bridge.client.isZonePinned(zone.id)) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                selectedClient = bridge.client
                                selectedZone = zone
                            }
                        }
                        .background(zoneDragTarget == zone.id ? dragTargetHighlight : Color.clear)
                        .onDrag {
                            draggingZoneId = zone.id
                            return NSItemProvider(object: zone.id as NSString)
                        }
                        .onDrop(of: [.text], delegate: ReorderDropDelegate(
                            targetId: zone.id,
                            draggingId: $draggingZoneId,
                            dragTarget: $zoneDragTarget,
                            onMove: { fromId, toId in bridge.client.moveZone(fromId: fromId, toId: toId) }
                        ))
                        .contextMenu {
                            Button(bridge.client.isZonePinned(zone.id) ? "Unpin" : "Pin to Top") {
                                withAnimation { bridge.client.toggleZonePin(zone.id) }
                            }
                            if let idx = bridge.client.zones.firstIndex(where: { $0.id == zone.id }), idx > 0 {
                                Button("Move Up") {
                                    bridge.client.moveZone(fromId: zone.id, toId: bridge.client.zones[idx - 1].id)
                                }
                            }
                            if let idx = bridge.client.zones.firstIndex(where: { $0.id == zone.id }), idx < bridge.client.zones.count - 1 {
                                Button("Move Down") {
                                    bridge.client.moveZone(fromId: zone.id, toId: bridge.client.zones[idx + 1].id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Single-Bridge Content

    @ViewBuilder
    private var singleBridgeContent: some View {
        if let client = primaryClient {
            if client.isLoading && client.rooms.isEmpty && client.zones.isEmpty {
                Spacer()
                ProgressView("Loading…")
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let error = client.lastError {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                                .font(.caption)
                                .padding(.horizontal)
                        }

                        // Rooms
                        sectionHeader("Rooms", icon: "house")

                        ForEach(client.rooms) { room in
                            LightRowView(apiClient: client, name: room.name, archetype: room.metadata.archetype, groupedLightId: room.groupedLightId, groupId: room.id, isPinned: client.isRoomPinned(room.id)) {
                                withAnimation(.easeInOut(duration: 0.25)) { selectedRoom = room }
                            }
                            .background(roomDragTarget == room.id ? dragTargetHighlight : Color.clear)
                            .onDrag {
                                draggingRoomId = room.id
                                return NSItemProvider(object: room.id as NSString)
                            }
                            .onDrop(of: [.text], delegate: ReorderDropDelegate(
                                targetId: room.id,
                                draggingId: $draggingRoomId,
                                dragTarget: $roomDragTarget,
                                onMove: { fromId, toId in client.moveRoom(fromId: fromId, toId: toId) }
                            ))
                            .contextMenu {
                                Button(client.isRoomPinned(room.id) ? "Unpin" : "Pin to Top") {
                                    withAnimation { client.toggleRoomPin(room.id) }
                                }
                                if let idx = client.rooms.firstIndex(where: { $0.id == room.id }), idx > 0 {
                                    Button("Move Up") {
                                        client.moveRoom(fromId: room.id, toId: client.rooms[idx - 1].id)
                                    }
                                }
                                if let idx = client.rooms.firstIndex(where: { $0.id == room.id }), idx < client.rooms.count - 1 {
                                    Button("Move Down") {
                                        client.moveRoom(fromId: room.id, toId: client.rooms[idx + 1].id)
                                    }
                                }
                            }
                        }

                        // Zones
                        if !client.zones.isEmpty {
                            sectionHeader("Zones", icon: "square.grid.2x2")

                            ForEach(client.zones) { zone in
                                LightRowView(apiClient: client, name: zone.name, archetype: zone.metadata.archetype, groupedLightId: zone.groupedLightId, groupId: zone.id, isPinned: client.isZonePinned(zone.id)) {
                                    withAnimation(.easeInOut(duration: 0.25)) { selectedZone = zone }
                                }
                                .background(zoneDragTarget == zone.id ? dragTargetHighlight : Color.clear)
                                .onDrag {
                                    draggingZoneId = zone.id
                                    return NSItemProvider(object: zone.id as NSString)
                                }
                                .onDrop(of: [.text], delegate: ReorderDropDelegate(
                                    targetId: zone.id,
                                    draggingId: $draggingZoneId,
                                    dragTarget: $zoneDragTarget,
                                    onMove: { fromId, toId in client.moveZone(fromId: fromId, toId: toId) }
                                ))
                                .contextMenu {
                                    Button(client.isZonePinned(zone.id) ? "Unpin" : "Pin to Top") {
                                        withAnimation { client.toggleZonePin(zone.id) }
                                    }
                                    if let idx = client.zones.firstIndex(where: { $0.id == zone.id }), idx > 0 {
                                        Button("Move Up") {
                                            client.moveZone(fromId: zone.id, toId: client.zones[idx - 1].id)
                                        }
                                    }
                                    if let idx = client.zones.firstIndex(where: { $0.id == zone.id }), idx < client.zones.count - 1 {
                                        Button("Move Down") {
                                            client.moveZone(fromId: zone.id, toId: client.zones[idx + 1].id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        } else {
            Spacer()
            ProgressView("Loading…")
            Spacer()
        }
    }

    // MARK: - Subviews

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.top, 4)
    }
}

// MARK: - Drag-and-Drop Reordering

/// DropDelegate that handles in-app reordering via @State-tracked drag source ID.
/// Uses the older onDrag/onDrop API which works more reliably in MenuBarExtra panels
/// than the newer dropDestination(for:) API.
struct ReorderDropDelegate: DropDelegate {
    let targetId: String
    @Binding var draggingId: String?
    @Binding var dragTarget: String?
    let onMove: (String, String) -> Void

    func dropEntered(info: DropInfo) {
        dragTarget = targetId
    }

    func dropExited(info: DropInfo) {
        dragTarget = nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggingId != nil && draggingId != targetId
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let fromId = draggingId, fromId != targetId else { return false }
        onMove(fromId, targetId)
        draggingId = nil
        dragTarget = nil
        return true
    }
}
