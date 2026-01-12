import Fluent
import Vapor

func routes(_ app: Application) throws {
    app.get { req async in
        req.redirect(to: "https://proxlock.dev")
    }

    app.get("version") { req async -> String in
        "Running commit: %%REPLACE_HERE_IN_CI%%"
    }
    
    try registerV1Routes(app.grouped("v1"))
    try registerV1Routes(app)
    
    // Webhooks
    let webhooks = app.grouped("webhooks")
    try webhooks.register(collection: ClerkSubscriptionsWebhook())
}

private let rateLimitManager = RateLimitManager()
private let googleCloudAuthStore: GoogleCloudAuthStore = GoogleCloudAuthStore()

private func registerV1Routes<R: RoutesBuilder>(_ v1: R) throws {
    // Proxy Route
    try v1.grouped(RateLimitMiddleware(manager: rateLimitManager)).grouped(DeviceValidationMiddleware(googleCloudAuthStore: googleCloudAuthStore)).register(collection: RequestProxyController())
    
    // Admin Route
    let adminRoute = v1.grouped("admin").grouped(ClerkAuthenticator())
    try adminRoute.grouped(":userID").register(collection: UserController()) // /admin/:userID/user
    
    // Dashboard Routes
    
    let v1_authenticatedRouters = v1.grouped(ClerkAuthenticator())
    
    try v1_authenticatedRouters.register(collection: UserController())
    try v1_authenticatedRouters.register(collection: APIKeyController())
    try v1_authenticatedRouters.register(collection: ProjectController())
    try v1_authenticatedRouters.register(collection: DeviceCheckKeyController())
    try v1_authenticatedRouters.register(collection: PlayIntegrityConfigController())
}
