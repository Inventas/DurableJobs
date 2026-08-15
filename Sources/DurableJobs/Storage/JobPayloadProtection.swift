import Foundation

public protocol JobPayloadProtection: Sendable {
    func protect(_ payload: Data) throws -> Data
    func unprotect(_ payload: Data) throws -> Data
}
