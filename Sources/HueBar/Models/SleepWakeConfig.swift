import Foundation

/// Enum defining the sleep/wake automation mode for a room or zone.
enum SleepWakeMode: String, Codable, CaseIterable, Sendable {
    case sleepOnly = "sleep"
    case wakeOnly = "wake"
    case both = "both"
}

/// Configuration for automatic sleep/wake scene recall for a room or zone.
///
/// This struct defines rules for automatically recalling scenes when the system
/// sleeps or wakes up. One configuration applies per room/zone, with the
/// targetId serving as the unique identifier.
struct SleepWakeConfig: Codable, Sendable, Identifiable {
    /// The type of target (room, zone, etc.) this configuration applies to.
    let targetType: HotkeyBinding.TargetType
    
    /// The unique identifier of the target (room/zone ID).
    let targetId: String
    
    /// The human-readable name of the target for display purposes.
    let targetName: String
    
    /// The sleep/wake automation mode for this target.
    let mode: SleepWakeMode
    
    /// Optional scene ID to recall when the system wakes up.
    let wakeSceneId: String?
    
    /// Optional display name of the wake scene.
    let wakeSceneName: String?
    
    /// Unique identifier for this configuration based on the target.
    var id: String { targetId }
}
