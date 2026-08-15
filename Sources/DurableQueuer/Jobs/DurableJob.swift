import Foundation

public protocol DurableJob: Codable, Sendable {
    static var typeIdentifier: String { get }
    static var payloadVersion: Int { get }
    static var defaults: JobDefaults { get }
}

extension DurableJob {
    public static var payloadVersion: Int { 1 }
    public static var defaults: JobDefaults { .init() }
}
