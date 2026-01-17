//
//  DeviceValidationMiddleware.swift
//  APIProxy
//
//  Created by Morris Richman on 10/10/25.
//

import Foundation
import Vapor
import VaporDeviceCheck
import Fluent
import JWTKit
@preconcurrency import IAMServiceAccountCredentials
import Core

actor GoogleCloudAuthStore {
    private var clients: [String: IAMServiceAccountCredentialsClient] = [:]
    
    func client(for config: PlayIntegrityConfig, request: Request) throws -> IAMServiceAccountCredentialsClient {
        let serviceAccount = try config.configData
        if let existingClient = clients[serviceAccount.projectId] {
            return existingClient
        }
        
        let iamConfig = IAMServiceAccountCredentialsConfiguration(scope: [.playIntegrity], serviceAccount: serviceAccount.clientEmail, project: serviceAccount.projectId)
        let iam = try IAMServiceAccountCredentialsClient(credentials: .init(project: serviceAccount.projectId, credentials: serviceAccount.asString()), config: iamConfig, httpClient: .shared, eventLoop: request.eventLoop)
        
        clients[serviceAccount.projectId] = iam
        
        return iam
    }
}

struct DeviceValidationMiddleware: AsyncMiddleware {
    let googleCloudAuthStore: GoogleCloudAuthStore
    let apiKeyDataLinkingMigrationController: APIKeyDataLinkingMigrationController
    
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let modeString = request.headers.first(name: DeviceValidationHeaderKeys.validationMode), let mode = DeviceValidationMode(rawValue: modeString) else {
            throw Abort(.unauthorized, reason: "Failed Device Validation: Mode not detected")
        }
        
        switch mode {
        case .deviceCheck:
            return try await handleDeviceCheck(to: request, chainingTo: next)
        case .playIntegrity:
            return try await handlePlayIntegrity(to: request, chainingTo: next)
        case .web:
            return try await handleWeb(to: request, chainingTo: next)
        }
    }
    
    private func handleWeb(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let dbKey = try await getDBKey(from: request)
        
        guard dbKey.allowsWeb else {
            throw Abort(.unauthorized, reason: "Web requests are not enabled for this key")
        }
        
        let deviceCheckEventLoopFuture = wildcardCorsMiddleware.respond(to: request, chainingTo: next)
        
        let response = try await withCheckedThrowingContinuation { continuation in
            deviceCheckEventLoopFuture.whenComplete { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
        
        return response
    }
    
    // MARK: – Play Integrity    
    private func handlePlayIntegrity(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let dbKey = try await getDBKey(from: request)
        
        guard let googlePlayKey = request.headers.first(name: "X-Play-Integrity-Key") else {
            throw Abort(.unauthorized, reason: "Play Integrity Key was not found")
        }
        
        let integrityConfig = try await apiKeyDataLinkingMigrationController.getPlayIntegrityConfig(for: dbKey, from: request)
        
        // Allow bypass token
        guard integrityConfig.bypassToken != googlePlayKey else {
            return try await next.respond(to: request)
        }
        
        let client = try await googleCloudAuthStore.client(for: integrityConfig, request: request)
        
        let postMessage = PlayIntegrityPayload(integrityToken: googlePlayKey)
        let postData = try JSONEncoder().encode(postMessage)
        
        let response = try await withCheckedThrowingContinuation { continuation in
            let sendRequest: EventLoopFuture<PlayIntegrityResponse> = client.request.send(method: .POST, path: "https://playintegrity.googleapis.com/v1/\(integrityConfig.packageName):decodeIntegrityToken", body: .data(postData), eventLoop: request.eventLoop)
            sendRequest.whenComplete { result in
                switch result {
                case .success(let success):
                    continuation.resume(returning: success)
                case .failure(let failure):
                    continuation.resume(throwing: failure)
                }
            }
        }.tokenPayloadExternal
        
        guard response.deviceIntegrity.deviceRecognitionVerdict?.contains(.meetsDeviceIntegrity) == true && response.appIntegrity.appRecognitionVerdict == .playRecognized else {
            throw Abort(.forbidden, reason: "Invalid Play Integrity")
        }
        
        return try await next.respond(to: request)
    }
    
    // MARK: – Device Check    
    private func handleDeviceCheck(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        // Get Project so we can fetch the user
        let dbKey = try await getDBKey(from: request)
        let key = try await apiKeyDataLinkingMigrationController.getDeviceCheckKey(for: dbKey, from: request)
        
        let kid = JWKIdentifier(string: key.keyID)
        let privateKey = try ES256PrivateKey(pem: Data(key.secretKey.utf8))
        
        // Add ECDSA key with JWKIdentifier
        await request.application.jwt.keys.add(ecdsa: privateKey, kid: kid)
        
        let deviceCheckMiddleware = DeviceCheck(
            jwkKid: kid,
            jwkIss: key.teamID,
            excludes: [["health"]],
            bypassTokens: [key.bypassToken]
        )
        
        let deviceCheckEventLoopFuture = deviceCheckMiddleware.respond(to: request, chainingTo: next)
        
        let response = try await withCheckedThrowingContinuation { continuation in
            deviceCheckEventLoopFuture.whenComplete { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
        
        return response
    }
    
    private func getDBKey(from request: Request) async throws -> APIKey {
        guard let associationId = request.headers.first(name: ProxyHeaderKeys.associationId) else {
            throw Abort(.unauthorized, reason: "Failed Device Validation: Association ID not detected")
        }
        
        // Get Project so we can fetch the user
        guard let dbKey = try await APIKey.find(UUID(uuidString: associationId), on: request.db) else {
            throw Abort(.unauthorized, reason: "Key was not found")
        }
        
        return dbKey
    }
}

struct DeviceValidationHeaderKeys {
    static let validationMode = "ProxLock_VALIDATION_MODE"
    static let appleTeamID = "ProxLock_APPLE_TEAM_ID"
}

enum DeviceValidationMode: String, Codable, CaseIterable {
    case deviceCheck = "device-check"
    case web = "web"
    case playIntegrity = "play-integrity"
}

extension GoogleCloudCredentialsConfiguration {
    init(project: String? = nil, credentials: String? = nil) throws {
        try self.init(projectId: project)
        
        guard let credentials else {
            return
        }
        
        self.serviceAccountCredentials = try? .init(fromJsonString: credentials)
        self.applicationDefaultCredentials = try? .init(fromJsonString: credentials)
    }
}

private struct PlayIntegrityPayload: Content, GoogleCloudModel {
    let integrityToken: String
    
    enum CodingKeys: String, CodingKey {
        case integrityToken = "integrity_token"
    }
}

private struct PlayIntegrityResponse: Content, GoogleCloudModel {
    let tokenPayloadExternal: Response
    
    struct Response: Codable {
        let requestDetails: RequestDetails
        let appIntegrity: AppIntegrity
        let deviceIntegrity: DeviceIntegrity
        let accountDetails: AccountDetails
        let environmentDetails: EnvironmentDetails?
    }
    
    // MARK: - AccountDetails
    struct AccountDetails: Codable {
        let appLicensingVerdict: Verdict
        
        enum Verdict: String, Codable {
            case licensed = "LICENSED"
            case unlicensed = "UNLICENSED"
            case unevaluated = "UNEVALUATED"
        }
    }
    
    // MARK: - AppIntegrity
    struct AppIntegrity: Codable {
        let appRecognitionVerdict: Verdict
        let packageName: String?
        let certificateSha256Digest: [String]?
        let versionCode: String?
        
        enum Verdict: String, Codable {
            case playRecognized = "PLAY_RECOGNIZED"
            case unrecognizedVersion = "UNRECOGNIZED_VERSION"
            case unevaluated = "UNEVALUATED"
        }
    }
    
    // MARK: - DeviceIntegrity
    struct DeviceIntegrity: Codable {
        let deviceRecognitionVerdict: [Verdict]?
        
        enum Verdict: String, Codable {
            case meetsBasicIntegrity = "MEETS_BASIC_INTEGRITY"
            case meetsDeviceIntegrity = "MEETS_DEVICE_INTEGRITY"
            case meetsStrongIntegrity = "MEETS_STRONG_INTEGRITY"
        }
    }
    
    // MARK: - RequestDetails
    struct RequestDetails: Codable {
        let requestPackageName, timestampMillis, nonce: String
    }
    
    // MARK: - EnvironmentDetails
    struct EnvironmentDetails: Codable {
        let appAccessRiskVerdict: AppAccessRiskVerdict?
        let playStoreAppAccessRiskVerdict: PlayStoreAppAccessRiskVerdict?
        
        struct AppAccessRiskVerdict: Codable {
            let appsDetected: [Verdict]
            
            enum Verdict: String, Codable {
                case knownInstalled = "KNOWN_INSTALLED"
                case knownCapturing = "KNOWN_CAPTURING"
                case knownControlling = "KNOWN_CONTROLLING"
                case knownOverlays = "KNOWN_OVERLAYS"
                case unknownInstalled = "UNKNOWN_INSTALLED"
                case unknownCapturing = "UNKNOWN_CAPTURING"
                case unknownControlling = "UNKNOWN_CONTROLLING"
                case unknownOverlays = "UNKNOWN_OVERLAYS"
            }
        }
        
        struct PlayStoreAppAccessRiskVerdict: Codable {
            let verdict: [Verdict]
            
            enum Verdict: String, Codable {
                case noIssues = "NO_ISSUES"
                case noData = "NO_DATA"
                case possibleRisk = "POSSIBLE_RISK"
                case mediumRisk = "MEDIUM_RISK"
                case highRisk = "HIGH_RISK"
                case unevaluated = "UNEVALUATED"
            }
        }
    }
}
