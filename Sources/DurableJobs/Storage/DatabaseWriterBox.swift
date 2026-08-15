import GRDB

/// GRDB writers serialize database access, but the protocol itself does not
/// declare `Sendable`. This immutable box is safe when used with a conforming
/// GRDB writer such as `DatabasePool` or `DatabaseQueue`.
final class DatabaseWriterBox: @unchecked Sendable {
    let value: any DatabaseWriter

    init(_ value: any DatabaseWriter) {
        self.value = value
    }
}
