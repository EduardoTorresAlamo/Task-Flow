import Foundation
import SwiftData

@Model final class Project {
    var id: UUID = UUID()
    var name: String
    var colorHex: String = "#6E56CF"
    var symbolName: String = "folder"
    var createdAt: Date = Date()
    @Relationship(deleteRule: .nullify, inverse: \Task.project) var tasks: [Task] = []

    init(name: String, colorHex: String = "#6E56CF", symbolName: String = "folder") {
        self.name = name
        self.colorHex = colorHex
        self.symbolName = symbolName
    }
}
