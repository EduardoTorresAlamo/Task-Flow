import Foundation
import SwiftData

@Model final class Task {
    var id: UUID = UUID()
    var title: String
    var notes: String = ""
    var dueDate: Date?
    var priority: Priority = Priority.none
    var isCompleted: Bool = false
    var completedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var eventKitIdentifier: String?

    @Relationship(deleteRule: .nullify) var project: Project?
    @Relationship(deleteRule: .cascade) var subtasks: [Task] = []
    var parentTask: Task?
    @Relationship var tags: [Tag] = []

    init(
        title: String,
        dueDate: Date? = nil,
        priority: Priority = .none,
        notes: String = ""
    ) {
        self.title = title
        self.dueDate = dueDate
        self.priority = priority
        self.notes = notes
    }
}
