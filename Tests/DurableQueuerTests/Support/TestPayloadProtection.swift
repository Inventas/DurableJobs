import DurableQueuer
import Foundation

struct TestPayloadProtection: JobPayloadProtection {
    func protect(_ payload: Data) throws -> Data {
        Data(payload.map { $0 ^ 0xA5 })
    }

    func unprotect(_ payload: Data) throws -> Data {
        Data(payload.map { $0 ^ 0xA5 })
    }
}
