//
//  Cors.swift
//  APIProxy
//
//  Created by Morris Richman on 10/10/25.
//

import Foundation
import Vapor

private let corsConfiguration = CORSMiddleware.Configuration(
    allowedOrigin: .any(["http://127.0.0.1:5173", "http://127.0.0.1:5174", "http://localhost:5173",  "http://localhost:5174", "https://proxlock.dev", "https://app.proxlock.dev", "https://admin.proxlock.dev"]),
    allowedMethods: [.GET, .POST, .PUT, .OPTIONS, .DELETE, .PATCH],
    allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith, .userAgent, .accessControlAllowOrigin],
    allowCredentials: true
)
let corsMiddleware = CORSMiddleware(configuration: corsConfiguration)

private let wildcardCorsConfiguration = CORSMiddleware.Configuration(
    allowedOrigin: .all,
    allowedMethods: [.GET, .POST, .PUT, .OPTIONS, .DELETE, .PATCH],
    allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith, .userAgent, .accessControlAllowOrigin],
    allowCredentials: false
)
let wildcardCorsMiddleware = CORSMiddleware(configuration: wildcardCorsConfiguration)
