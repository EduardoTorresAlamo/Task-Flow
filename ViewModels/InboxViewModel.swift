import SwiftUI
import SwiftData
import Observation

@Observable @MainActor final class InboxViewModel {
    var inputText = ""
    var parsedPreview: ParsedTaskInput?
    private let parser = NaturalLanguageParser()
    var modelContext: ModelContext
    private let calendarManager: CalendarManager

    init(modelContext: ModelContext, calendarManager: CalendarManager) {
        self.modelContext = modelContext
        self.calendarManager = calendarManager
    }

    func onInputChange() {
        parsedPreview = inputText.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil
            : parser.parse(inputText)
    }

    func commitTask() async {
        guard let parsed = parsedPreview, !parsed.title.isEmpty else { return }
        let task = Task(title: parsed.title, dueDate: parsed.dueDate, priority: parsed.priority, notes: parsed.notes)
        modelContext.insert(task)
        inputText = ""
        parsedPreview = nil
        await calendarManager.syncTask(task)
    }
}
