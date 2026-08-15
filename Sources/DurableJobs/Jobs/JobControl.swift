import Foundation

enum JobControl: Error, Sendable {
    case release(delay: TimeInterval, consumesAttempt: Bool)
    case permanentFailure(message: String)
}
