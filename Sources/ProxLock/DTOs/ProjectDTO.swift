import Fluent
import Vapor

struct ProjectDTO: Content {
    var id: UUID?
    var name: String?
    let description: String?
    let keys: [APIKeySendingDTO]?
    
    func toModel() -> Project {
        let model = Project()
        
        model.id = self.id
        if let description {
            model.userDescription = description
        }
        if let name = self.name {
            model.name = name
        }
        return model
    }
}
