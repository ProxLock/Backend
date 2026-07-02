//
//  Cors.swift
//  APIProxy
//
//  Created by Morris Richman on 10/10/25.
//

import Foundation
import Vapor

private func getAllowedOrigins() -> [String] {
    if let env = (try? Environment.detect()), env == .production {
        return ["https://proxlock.dev", "https://app.proxlock.dev", "https://admin.proxlock.dev"]
    } else {
        return ["http://127.0.0.1:5173", "http://0.0.0.0:5173", "http://127.0.0.1:5174", "http://localhost:5173",  "http://localhost:5174", "https://proxlock.dev", "https://app.proxlock.dev", "https://admin.proxlock.dev"]
    }
}

private let corsConfiguration = CORSMiddleware.Configuration(
    allowedOrigin: .any(getAllowedOrigins()),
    allowedMethods: [.GET, .POST, .PUT, .OPTIONS, .DELETE, .PATCH],
    allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith, .userAgent, .accessControlAllowOrigin, .code],
    allowCredentials: true,
    exposedHeaders: [.code]
)
private let corsMiddleware = CORSMiddleware(configuration: corsConfiguration)

extension HTTPHeaders.Name {
    static let code = HTTPHeaders.Name("Code")
}
struct corsSwitchMiddleware: Middleware {
    func respond(to request: Request, chainingTo next: any Responder) -> EventLoopFuture<Response> {

        guard (request.url.path.hasPrefix("/proxy")) else {
            return corsMiddleware.respond(to: request, chainingTo: next)
        }
        
        // creating the wildcard middleware
        let wildcardCorsMiddleware = CORSMiddleware(configuration: CORSMiddleware.Configuration(
            allowedOrigin: .custom(request.headers.first(name: .origin) ?? ""),
            allowedMethods: [.GET, .POST, .PUT, .OPTIONS, .DELETE, .PATCH],
            allowedHeaders: [HTTPHeaders.Name("*")],
            allowCredentials: true,
            exposedHeaders: [.code]
        ))
        return wildcardCorsMiddleware.respond(to: request, chainingTo: next)
    }
}
