import NIOSSL
import Fluent
import FluentPostgresDriver
import Vapor
import Queues

// configures your application
public func configure(_ app: Application) async throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    
    // cors middleware should come before default error middleware using `at: .beginning`
    app.middleware.use(corsMiddleware, at: .beginning)
    
    if let dbURL = Environment.get("DATABASE_URL") {
        app.logger.notice("DB URL: \(dbURL)")
        try app.databases.use(.postgres(configuration: .railwayCompatible(url: dbURL)), as: .psql)
    } else {
        app.logger.notice("DB Hostname: \(Environment.get("DATABASE_HOST") ?? "unknown")")
        app.databases.use(DatabaseConfigurationFactory.postgres(configuration: .init(
            hostname: Environment.get("DATABASE_HOST") ?? "localhost",
            port: Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? SQLPostgresConfiguration.ianaPortNumber,
            username: Environment.get("DATABASE_USERNAME") ?? "vapor_username",
            password: Environment.get("DATABASE_PASSWORD") ?? "vapor_password",
            database: Environment.get("DATABASE_NAME") ?? "vapor_database",
            tls: .prefer(try .init(configuration: .clientDefault)))
        ), as: .psql)
    }
    
    let jsonDecoder = JSONDecoder()
    jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
    ContentConfiguration.global.use(decoder: jsonDecoder, for: .json)
    
    // Set Request Body Maximum
    app.routes.defaultMaxBodySize = "100mb"

    // Set Migrations
    app.migrations.add(User.migrations)
    app.migrations.add(User.AccessKey.migrations)
    app.migrations.add(Project.migrations)
    app.migrations.add(DeviceCheckKey.migrations)
    app.migrations.add(PlayIntegrityConfig.migrations)
    app.migrations.add(APIKey.migrations)
    app.migrations.add(MonthlyUserUsageHistory.migrations)
    app.migrations.add(DailyUserUsageHistory.migrations)
    try await app.autoMigrate()
    
    // Schedule Jobs
    app.queues.schedule(CacheCleanupJob()).minutely()
    try app.queues.startScheduledJobs()

    // register routes
    try routes(app)
}

extension SQLPostgresConfiguration {
    static func railwayCompatible(url: String) throws -> SQLPostgresConfiguration {
        var configuration = try SQLPostgresConfiguration(url: url)

        guard
            let components = URLComponents(string: url),
            components.host?.hasSuffix(".railway.internal") == true
        else {
            return configuration
        }

        var tlsConfiguration = TLSConfiguration.makeClientConfiguration()
        tlsConfiguration.certificateVerification = .none
        configuration.coreConfiguration.tls = try .require(.init(configuration: tlsConfiguration))
        return configuration
    }
}
