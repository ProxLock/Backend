import Fluent
import Vapor

func routes(_ app: Application) throws {
    let commitHash: String = "%%REPLACE_HERE_IN_CI%%"
    
    app.get { req async in
        req.redirect(to: "https://proxlock.dev")
    }

    app.get("version") { req async -> String in
        "Running commit: \(commitHash)"
    }
    // Return in json form
    app.get("version.json") { req async -> String in
        "{\"commit_hash\": \"\(commitHash)\"}"
    }
    
    try registerV1Routes(app.grouped("v1"))
    try registerV1Routes(app)
    
    // Webhooks
    let webhooks = app.grouped("webhooks")
    try webhooks.register(collection: ClerkSubscriptionsWebhook())
}

private let rateLimitManager = RateLimitManager()
private let googleCloudAuthStore: GoogleCloudAuthStore = GoogleCloudAuthStore()
private let apiKeyDataLinkingMigrationController: APIKeyDataLinkingMigrationController = APIKeyDataLinkingMigrationController()

private func registerV1Routes<R: RoutesBuilder>(_ v1: R) throws {
    // Proxy Route
    try v1.grouped(RateLimitMiddleware(manager: rateLimitManager)).grouped(DeviceValidationMiddleware(googleCloudAuthStore: googleCloudAuthStore, apiKeyDataLinkingMigrationController: apiKeyDataLinkingMigrationController)).register(collection: RequestProxyController(apiKeyDataLinkingMigrationController: apiKeyDataLinkingMigrationController))
    
    // Admin Route
    let adminRoute = v1.grouped("admin").grouped(Authenticator())
    try adminRoute.register(collection: UserController())
    try adminRoute.register(collection: UserAccessKeyController())
    
    // Dashboard Routes
    
    let v1_authenticatedRouters = v1.grouped(Authenticator())
    
    try v1_authenticatedRouters.register(collection: UserController())
    try v1_authenticatedRouters.register(collection: UserAccessKeyController())
    try v1_authenticatedRouters.register(collection: APIKeyController())
    try v1_authenticatedRouters.register(collection: ProjectController())
    try v1_authenticatedRouters.register(collection: DeviceCheckKeyController())
    try v1_authenticatedRouters.register(collection: PlayIntegrityConfigController())
}
