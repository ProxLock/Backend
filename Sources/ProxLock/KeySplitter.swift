//
//  KeySplitter.swift
//  APIProxy
//
//  Created by Morris Richman on 10/4/25.
//

import Foundation
#if canImport(Security)
import Security
#else
import Crypto
#endif

/// Utility to split a key into two partial keys and reconstruct it
final class KeySplitter {
    
    /// Split a string key into two base64 partials
    /// - Parameter key: The original secret string (e.g. provider API key)
    /// - Returns: (serverShareB64, clientShareB64)
    static func split(key: String) throws -> (String, String) {
        let keyData = Data(key.utf8)
        
        // Generate random server share of the same length
        var randomBytes = [UInt8](repeating: 0, count: keyData.count)
        
        #if canImport(Security)
        let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        guard status == errSecSuccess else {
            throw NSError(domain: "KeySplitter", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to generate random bytes"])
        }
        #else
        // Linux fallback using CryptoKit (secure RNG)
        var rng = SystemRandomNumberGenerator()
        for i in 0..<randomBytes.count {
            randomBytes[i] = UInt8.random(in: 0...255, using: &rng)
        }
        #endif
        
        let serverShare = Data(randomBytes)
        
        // XOR server share with original to produce client share
        let clientShare = keyData.xor(with: serverShare)
        
        return (serverShare.base64EncodedString(),
                clientShare.base64EncodedString())
    }
    
    /// Recreate the original string key from the two partials
    /// - Parameters:
    ///   - serverShareB64: Base64 string of the server share
    ///   - clientShareB64: Base64 string of the client share
    /// - Returns: The original secret string
    static func reconstruct(serverShareB64: String,
                            clientShareB64: String) throws -> String {
        guard let serverData = Data(base64Encoded: serverShareB64),
              let clientData = Data(base64Encoded: clientShareB64) else {
            throw NSError(domain: "KeySplitter", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid base64 shares"])
        }
        
        let originalData = serverData.xor(with: clientData)
        return String(data: originalData, encoding: .utf8) ?? ""
    }
}

// MARK: - Data XOR helper
private extension Data {
    func xor(with other: Data) -> Data {
        let count = Swift.min(self.count, other.count)
        var result = Data(count: count)
        for i in 0..<count {
            result[i] = self[i] ^ other[i]
        }
        return result
    }
}
