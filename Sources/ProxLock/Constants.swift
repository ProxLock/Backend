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
    static let blacklistedProxyDestinations: Set<String> = Set([dbHostname] + (Environment.get("BLACKLISTED_PROXY_DESTINATIONS")?.components(separatedBy: ", ") ?? []))
    static let termsLastUpdated = Date(timeIntervalSince1970: TimeInterval(Environment.get("TERMS_LAST_UPDATED") ?? "") ?? 1767225600)
    static let minimumTermsDateForProxy = Date(timeIntervalSince1970: TimeInterval(Environment.get("MINIMUM_TERMS_DATE_FOR_PROXY") ?? "") ?? 1767225600)
}
