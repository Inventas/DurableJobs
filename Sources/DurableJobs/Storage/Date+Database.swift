import Foundation

extension Date {
    var databaseMilliseconds: Int64 {
        Int64((timeIntervalSince1970 * 1_000).rounded())
    }

    init(databaseMilliseconds: Int64) {
        self.init(timeIntervalSince1970: TimeInterval(databaseMilliseconds) / 1_000)
    }
}
