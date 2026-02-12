import Foundation

struct GroupedLight: Decodable, Sendable, Identifiable {
    let id: String
    let on: OnState?
    let dimming: DimmingState?
    
    var isOn: Bool { on?.on ?? false }
    var brightness: Double { dimming?.brightness ?? 0.0 }
}

struct OnState: Codable, Sendable {
    let on: Bool
}

struct DimmingState: Decodable, Sendable {
    let brightness: Double
}
