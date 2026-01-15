import Fluent
import Vapor
import struct Foundation.UUID

/// Property wrappers interact poorly with `Sendable` checking, causing a warning for the `@ID` property
/// It is recommended you write your model with sendability checking on and then suppress the warning
/// afterwards with `@unchecked Sendable`.
final class User: Model, Authenticatable, @unchecked Sendable {
    static let schema = "users"
    
    @ID
    var id: UUID?
    
    @Field(key: "clerk_id")
    var clerkID: String
    
    @OptionalEnum(key: "current_subscription")
    var currentSubscription: SubscriptionPlans?
    
    @Field(key: "override_monthly_request_limit")
    var overrideMonthlyRequestLimit: Int?
    
    @Field(key: "override_access_key_limit")
    var overrideAccessKeyLimit: Int?
    
    @Children(for: \.$user)
    var usageHistory: [MonthlyUserUsageHistory]
    
    @Children(for: \.$user)
    var projects: [Project]
    
    @Children(for: \.$user)
    var accessKey: [AccessKey]

    init() { }

    init(id: UUID? = nil, clerkID: String) {
        self.id = id
        self.clerkID = clerkID
    }
    
    func toDTO(on db: any Database) async throws -> UserDTO {
        try await $projects.load(on: db)
        let projects = try await $projects.get(on: db)
        let projectsDTOs = try await projects.asyncMap({ try await $0.toDTO(on: db) })
        let currentRecord = try await getOrCreateCurrentMonthlyHistoricalRecord(db: db)
        try await $accessKey.load(on: db)
        let apiKeys = try await $accessKey.get(on: db)
        
        return .init(
            id: self.clerkID,
            projects: projectsDTOs,
            currentSubscription: currentSubscription ?? .free,
            currentRequestUsage: currentRecord.requestCount,
            requestLimit: overrideMonthlyRequestLimit ?? (currentSubscription ?? .free).requestLimit,
            apiKeys: apiKeys.compactMap({ try? $0.toDTO() }),
            isAdmin: Constants.adminClerkIDs.contains(self.clerkID)
        )
    }
    
    func getOrCreateCurrentMonthlyHistoricalRecord(req: Request) async throws -> MonthlyUserUsageHistory {
        try await getOrCreateCurrentMonthlyHistoricalRecord(db: req.db)
    }
    
    func getOrCreateCurrentMonthlyHistoricalRecord(db: any Database) async throws -> MonthlyUserUsageHistory {
        // Get Historical Log
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = .gmt
        
        var historyEntry = try await MonthlyUserUsageHistory.query(on: db).filter(\.$month == Date().startOfMonth(calendar: calendar)).filter(\.$user.$id == requireID()).with(\.$user).first()
        
        if historyEntry == nil {
            let newEntry = MonthlyUserUsageHistory(requestCount: 0, subscription: currentSubscription ?? .free, month: Date().startOfMonth(calendar: calendar))
            
            newEntry.$user.id = try requireID()
            
            try await newEntry.save(on: db)
            
            historyEntry = newEntry
        }
        
        guard let historyEntry else {
            throw Abort(.internalServerError)
        }
        
        return historyEntry
    }
    
    final class AccessKey: Model, Authenticatable, @unchecked Sendable {
        static let schema = "user_access_keys"
        
        @ID(custom: .id)
        var id: String?
        
        @Field(key: "name")
        var name: String
        
        @Parent(key: "user_id")
        var user: User
        
        init() {
            self.id = "sk_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        }
        
        init(name: String) {
            self.id = "sk_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
            self.name = name
        }
        
        func toDTO() throws -> UserAPIKeyDTO {
            try .init(name: name, key: requireID())
        }
    }
}

extension Sequence {
    func asyncMap<T>(
        _ transform: (Element) async throws -> T
    ) async rethrows -> [T] {
        var values = [T]()

        for element in self {
            try await values.append(transform(element))
        }

        return values
    }
}

extension Date {
    func startOfMonth(calendar: Calendar = .autoupdatingCurrent) -> Date {
        var components = calendar.dateComponents([.year, .month], from: self)
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.nanosecond = 0
        return calendar.date(from: components) ?? self
    }
    
    func startOfDay(calendar: Calendar = .autoupdatingCurrent) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: self)
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.nanosecond = 0
        return calendar.date(from: components) ?? self
    }
}
