import Foundation

public enum RetryPolicy: Codable, Equatable, Sendable {
    case none
    case fixed(delay: TimeInterval)
    case exponentialFullJitter(base: TimeInterval, maximum: TimeInterval)

    public static let `default`: Self = .exponentialFullJitter(
        base: 5,
        maximum: 15 * 60
    )

    func delay(afterAttempt attempt: Int, randomUnit: Double) -> TimeInterval? {
        switch self {
        case .none:
            return nil
        case let .fixed(delay):
            return max(0, delay)
        case let .exponentialFullJitter(base, maximum):
            let exponent = Double(max(0, attempt - 1))
            let upperBound = min(maximum, base * pow(2, exponent))
            return max(0, min(1, randomUnit)) * max(0, upperBound)
        }
    }

    var validationIssue: String? {
        switch self {
        case .none:
            return nil
        case let .fixed(delay):
            return delay.isFinite && delay >= 0 ? nil : "fixed delay must be finite and nonnegative"
        case let .exponentialFullJitter(base, maximum):
            guard base.isFinite, base >= 0 else {
                return "jitter base must be finite and nonnegative"
            }
            guard maximum.isFinite, maximum >= base else {
                return "jitter maximum must be finite and at least the base"
            }
            return nil
        }
    }
}
