import NIOSSL
import Fluent
import FluentPostgresDriver
import Vapor

// configures your application
public func configure(_ app: Application) async throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    
    // cors middleware should come before default error middleware using `at: .beginning`
    app.middleware.use(corsMiddlewear, at: .beginning)
    
    app.databases.use(DatabaseConfigurationFactory.postgres(configuration: .init(
        hostname: Environment.get("DATABASE_HOST") ?? "localhost",
        port: Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? SQLPostgresConfiguration.ianaPortNumber,
        username: Environment.get("DATABASE_USERNAME") ?? "vapor_username",
        password: Environment.get("DATABASE_PASSWORD") ?? "vapor_password",
        database: Environment.get("DATABASE_NAME") ?? "vapor_database",
        tls: .disable)
    ), as: .psql)

    app.migrations.add(User.migrations)
    app.migrations.add(Project.migrations)
    app.migrations.add(APIKey.migrations)
    app.migrations.add(DeviceCheckKey.migrations)
    try await app.autoMigrate()

    // register routes
    try routes(app)
}
