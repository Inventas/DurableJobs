import Foundation

public struct EncodedJobPayload: Equatable, Sendable {
    public let typeIdentifier: String
    public let version: Int
    public let data: Data

    public init(
        typeIdentifier: String,
        version: Int,
        data: Data
    ) {
        self.typeIdentifier = typeIdentifier
        self.version = version
        self.data = data
    }
}
