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
    
    @Children(for: \.$user)
    var usageHistory: [UserUsageHistory]
    
    @Children(for: \.$user)
    var projects: [Project]

    init() { }

    init(id: UUID? = nil, clerkID: String) {
        self.id = id
        self.clerkID = clerkID
    }
    
    func toDTO(on db: any Database) async throws -> UserDTO {
        try await $projects.load(on: db)
        let projects = try await $projects.get(on: db)
        let projectsDTOs = try await projects.asyncMap({ try await $0.toDTO(on: db) })
        
        return .init(
            id: self.clerkID,
            projects: projectsDTOs,
            currentSubscription: currentSubscription
        )
    }
    
    func getOrCreateCurrentHistoricalRecord(req: Request) async throws -> UserUsageHistory {
        // Get Historical Log
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = .gmt
        
        var historyEntry = try await UserUsageHistory.query(on: req.db).filter(\.$month == Date().startOfMonth(calendar: calendar)).filter(\.$user.$id == requireID()).with(\.$user).first()
        
        if historyEntry == nil {
            let newEntry = UserUsageHistory(requestCount: 0, subscription: currentSubscription ?? .free, month: Date().startOfMonth())
            
            newEntry.$user.id = try requireID()
            
            try await newEntry.save(on: req.db)
            
            historyEntry = newEntry
        }
        
        guard let historyEntry else {
            throw Abort(.internalServerError)
        }
        
        return historyEntry
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
