import Fluent
import Vapor

struct UserDTO: Content {
    var id: String?
    let projects: [ProjectDTO]?
}
