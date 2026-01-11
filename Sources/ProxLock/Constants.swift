//
//  Contants.swift
//  ProxLock
//
//  Created by Morris Richman on 1/11/26.
//

import Vapor

struct Constants {
    static let adminClerkIDs: [String] = Environment.get("CLERK_ADMIN_IDS")?.components(separatedBy: ", ") ?? []
    static let clerkWebhookSecret: String = Environment.get("CLERK_WEBHOOK_SECRET")!
}
