import Fluent
import Vapor

func routes(_ app: Application) throws {
app.get { req async in
        "It works!"
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

private func registerV1Routes<R: RoutesBuilder>(_ v1: R) throws {
    try v1.grouped(DeviceValidationMiddleware()).register(collection: RequestProxyController())
    
    let v1_authenticatedRouters = v1.grouped(ClerkAuthenticator())
    
    try v1_authenticatedRouters.register(collection: UserController())
    try v1_authenticatedRouters.register(collection: APIKeyController())
    try v1_authenticatedRouters.register(collection: ProjectController())
    try v1_authenticatedRouters.register(collection: DeviceCheckKeyController())
}
