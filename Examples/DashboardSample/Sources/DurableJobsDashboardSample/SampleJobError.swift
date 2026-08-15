import Foundation

enum SampleJobError: LocalizedError {
    case plannedFailure(String)

    var errorDescription: String? {
        switch self {
        case let .plannedFailure(name):
            return "The sample job \"\(name)\" failed as requested."
        }
    }
}
