//
//  ClerkWebhookManager.swift
//  ProxLock
//
//  Created by Morris Richman on 11/14/25.
//

import Foundation
import Vapor
import CryptoKit

/// A class for holding common Clerk webhook data and functions.
class ClerkWebhookManager {
    private static let secret: String = Environment.get("CLERK_WEBHOOK_SECRET")!
    
    /// Generates Svix-style webhook signatures (HMAC-SHA256, base64).
    static func svixSignature(svixID: String, svixTimestamp: String, body: String) -> String? {
        // 1. Construct signed content
        let signedContent = "\(svixID).\(svixTimestamp).\(body)"
        
        // 2. Extract and Base64-decode key (after underscore)
        guard
            let encodedKey = secret.split(separator: "_").last,
            let keyData = Data(base64Encoded: String(encodedKey))
        else {
            return nil
        }

        // 3. Compute HMAC-SHA256
        let key = SymmetricKey(data: keyData)
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(signedContent.utf8),
            using: key
        )

        // 4. Base64 output
        return Data(mac).base64EncodedString()
    }
    
    static func isSivxSignatureValid(svixID: String, svixTimestamp: String, svixSignature: String, body: String) -> Bool {
        guard let expectedSignature = Self.svixSignature(svixID: svixID, svixTimestamp: svixTimestamp, body: body) else {
            return false
        }
        
        let signatures = svixSignature.split(separator: " ").map({ String($0).replacingOccurrences(of: "v1,", with: "") })
        
        return signatures.contains(expectedSignature)
    }
}
