import Foundation

struct HueResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let errors: [HueError]
    let data: [T]
}

struct HueError: Decodable, Sendable {
    let description: String
}
