import Vapor

extension UserController {
    private struct WebSocketOverrideLimitRequest: Content {
        var connectionSecondLimit: Int64?
        var messageUnitLimit: Int64?
    }

    /// POST /admin/:userID/user/websocket-override-limit
    ///
    /// Sets or clears the WebSocket billing override limits for a user.
    @Sendable
    func overrideWebSocketLimit(req: Request) async throws -> UserDTO {
        let user = try req.auth.require(User.self)
        let value = (try? req.content.decode(WebSocketOverrideLimitRequest.self)) ?? WebSocketOverrideLimitRequest()

        user.overrideMonthlyWebSocketConnectionSecondLimit = value.connectionSecondLimit
        user.overrideMonthlyWebSocketMessageUnitLimit = value.messageUnitLimit
        try await user.save(on: req.db)

        return try await user.toDTO(on: req.db)
    }
}
