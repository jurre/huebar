import Foundation

struct OnState: Codable, Sendable {
    let on: Bool
}

struct DimmingState: Codable, Sendable {
    let brightness: Double
}
