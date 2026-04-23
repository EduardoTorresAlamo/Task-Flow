import Foundation
import NaturalLanguage

struct ParsedTaskInput {
    var title: String
    var dueDate: Date?
    var priority: Priority
    var notes: String
}

struct NaturalLanguageParser {
    private let dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    func parse(_ input: String) -> ParsedTaskInput {
        let dueDate  = extractDate(from: input)
        let priority = extractPriority(from: input)
        let notes    = extractNotes(from: input)
        let title    = buildTitle(from: input, date: dueDate, notes: notes)
        return ParsedTaskInput(title: title, dueDate: dueDate, priority: priority, notes: notes)
    }

    private func extractDate(from text: String) -> Date? {
        let range = NSRange(text.startIndex..., in: text)
        return dateDetector?.firstMatch(in: text, range: range)?.date
    }

    private func extractPriority(from text: String) -> Priority {
        let lower = text.lowercased()
        if lower.contains("urgent") || lower.contains("asap") || lower.contains("critical") { return .high }
        if lower.contains("important") || lower.contains("high priority") || lower.contains("must") || lower.contains("need to") { return .medium }
        if lower.contains("low priority") || lower.contains("whenever") || lower.contains("someday") || lower.contains("no rush") || lower.contains("eventually") { return .low }
        return .none
    }

    private func extractNotes(from text: String) -> String {
        let connectors = ["to discuss", "regarding", "concerning", "notes:", "note:", "about"]
        let lower = text.lowercased()
        for connector in connectors {
            if let range = lower.range(of: connector) {
                let after = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !after.isEmpty { return after }
            }
        }
        return ""
    }

    private func buildTitle(from text: String, date: Date?, notes: String) -> String {
        var result = text

        // Remove notes segment from the connector word onward
        if !notes.isEmpty {
            let connectors = ["to discuss", "regarding", "concerning", "notes:", "note:", "about"]
            let lower = result.lowercased()
            for connector in connectors {
                if let range = lower.range(of: connector) {
                    let offset = result.distance(from: result.startIndex, to: range.lowerBound)
                    let idx = result.index(result.startIndex, offsetBy: offset)
                    result = String(result[..<idx])
                    break
                }
            }
        }

        // Remove detected date string
        if date != nil {
            let range = NSRange(result.startIndex..., in: result)
            if let match = dateDetector?.firstMatch(in: result, range: range),
               let swiftRange = Range(match.range, in: result) {
                result = result.replacingCharacters(in: swiftRange, with: "")
            }
        }

        // Remove priority keywords
        let priorityMarkers = ["urgent", "asap", "critical", "high priority", "important",
                               "must", "need to", "low priority", "whenever", "someday",
                               "no rush", "eventually"]
        for marker in priorityMarkers {
            result = result.replacingOccurrences(of: marker, with: "", options: .caseInsensitive)
        }

        // Remove common speech filler prefixes
        let fillers = ["remind me to", "remind me", "add task", "task:", "todo:", "to do:"]
        var lower = result.lowercased().trimmingCharacters(in: .whitespaces)
        for filler in fillers {
            if lower.hasPrefix(filler) {
                result = String(result.dropFirst(filler.count))
                lower = result.lowercased().trimmingCharacters(in: .whitespaces)
            }
        }

        let clean = result
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? text : clean
    }
}
