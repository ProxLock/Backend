import Fluent

protocol Migratable {
    /// All migrations for a class
    static var migrations: [any Migration] { get }
}
