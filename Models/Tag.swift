import Foundation
import SwiftData

@Model final class Tag {
    var id: UUID = UUID()
    var name: String
    var colorHex: String = "#FF6B6B"
    @Relationship(inverse: \Task.tags) var tasks: [Task] = []

    init(name: String, colorHex: String = "#FF6B6B") {
        self.name = name
        self.colorHex = colorHex
    }
}
