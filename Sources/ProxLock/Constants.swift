//
//  Contants.swift
//  ProxLock
//
//  Created by Morris Richman on 1/11/26.
//

import Vapor

struct Constants {
    static let adminClerkIDs: Set<String> = Set(Environment.get("CLERK_ADMIN_IDS")?.components(separatedBy: ", ") ?? [])
    static let clerkWebhookSecret: String = Environment.get("CLERK_WEBHOOK_SECRET")!
    static let dbHostname = Environment.get("DATABASE_HOST") ?? "localhost"
    static let blacklistedProxyDestinations: Set<String> = makeBlacklistedProxyDestinations()
    static let proxyBlockPrivateAddresses: Bool = Bool(Environment.get("PROXY_BLOCK_PRIVATE_ADDRESSES") ?? "true") ?? true
    static let termsLastUpdated = Date(timeIntervalSince1970: TimeInterval(Environment.get("TERMS_LAST_UPDATED") ?? "") ?? 1767225600)
    static let minimumTermsDateForProxy = Date(timeIntervalSince1970: TimeInterval(Environment.get("MINIMUM_TERMS_DATE_FOR_PROXY") ?? "") ?? 1767225600)
    
    static func isBlacklistedProxyDestination(_ destination: String) -> Bool {
        if proxyBlockPrivateAddresses, destination == "localhost" || destination == "127.0.0.1" || destination.starts(with: "192.") || destination.starts(with: "10.") || destination.starts(with: "172.") {
            return false
        }
        
        return blacklistedProxyDestinations.contains(destination)
    }
    
    private static func makeBlacklistedProxyDestinations() -> Set<String> {
        let initialSet = Set([dbHostname] + (Environment.get("BLACKLISTED_PROXY_DESTINATIONS")?.components(separatedBy: ", ") ?? []))
        
        let completeSet = initialSet.reduce(into: Set<String>()) { result, string in
            let splitString = string.split(separator: "/")
            if splitString.count == 2, let maskString = splitString.last, let mask = Int(maskString) {
                result.formUnion(resolveIPWildcards(String(splitString.first!), mask: mask))
            } else {
                result.insert(string)
            }
        }
        
        return completeSet
    }
    
    private static func resolveIPWildcards(_ base: String, mask: Int) -> Set<String> {
        let parts = base.split(separator: ".").compactMap { Int($0) }
        
        guard parts.count == 4,
              parts.allSatisfy({ 0...255 ~= $0 }),
              0...32 ~= mask
        else {
            return []
        }

        // Convert IP -> UInt32
        let ip =
            (UInt32(parts[0]) << 24) |
            (UInt32(parts[1]) << 16) |
            (UInt32(parts[2]) << 8)  |
            UInt32(parts[3])

        let hostBits = 32 - mask
        let networkMask: UInt32 =
            mask == 0 ? 0 : (~UInt32(0) << hostBits)

        let network = ip & networkMask
        let count = 1 << hostBits

        var results = Set<String>()

        for i in 0..<count {
            let current = network | UInt32(i)

            let a = (current >> 24) & 255
            let b = (current >> 16) & 255
            let c = (current >> 8) & 255
            let d = current & 255

            results.insert("\(a).\(b).\(c).\(d)")
        }

        return results
    }
}
