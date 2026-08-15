import Foundation

public struct JobRequest: Codable, Sendable {
    let typeIdentifier: String
    let payload: Data
    let payloadVersion: Int
    let defaults: JobDefaults
    let options: DispatchOptions

    public init<J: DurableJob>(
        _ job: J,
        options: DispatchOptions = .defaults
    ) throws {
        typeIdentifier = J.typeIdentifier
        payload = try JobPayloadCodec.encoder().encode(job)
        payloadVersion = J.payloadVersion
        defaults = J.defaults
        self.options = options
    }

    init(
        typeIdentifier: String,
        payload: Data,
        payloadVersion: Int,
        defaults: JobDefaults,
        options: DispatchOptions
    ) {
        self.typeIdentifier = typeIdentifier
        self.payload = payload
        self.payloadVersion = payloadVersion
        self.defaults = defaults
        self.options = options
    }
}
