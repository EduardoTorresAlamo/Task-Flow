import Foundation
import NaturalLanguage

/// The structured output produced by `NaturalLanguageParser.parse(_:)`.
///
/// Each field holds a value extracted from the raw input string. Fields
/// that could not be inferred carry their zero-value defaults (`nil` for
/// optionals, `.none` for priority, `""` for notes).
struct ParsedTaskInput {
    /// The cleaned task title with date strings, priority keywords,
    /// and speech fillers removed.
    var title: String
    /// The first calendar date found in the input, or `nil` if none was detected.
    var dueDate: Date?
    /// The priority inferred from keyword matching against the input.
    var priority: Priority
    /// Any supplementary text found after a recognized note connector word.
    var notes: String
}

/// Parses a free-form natural-language string into a structured `ParsedTaskInput`.
///
/// The parser uses `NSDataDetector` for date extraction and keyword matching
/// for priority and note inference. It does not make network calls and has no
/// external dependencies, so parsing is synchronous and can run on any thread.
///
/// Typical inputs include dictated speech ("remind me to call John tomorrow at 3pm urgent")
/// and typed freeform text ("meeting with Sarah regarding Q3 review on Friday").
struct NaturalLanguageParser {
    /// `NSDataDetector` configured to recognise calendar date expressions
    /// (e.g. "tomorrow", "next Friday", "June 5th at 2pm") in plain text.
    ///
    /// Created with `try?` because the underlying `NSRegularExpression` initialiser
    /// can theoretically throw, though it never does for the `.date` type constant.
    private let dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    /// Parses the given string and returns a `ParsedTaskInput` with all
    /// extractable fields populated.
    ///
    /// The parse order matters: notes and dates are extracted first, then the
    /// title is built by stripping those segments from the original text.
    ///
    /// - Parameter input: The raw user input string to parse.
    /// - Returns: A `ParsedTaskInput` with extracted fields. All fields have
    ///   safe defaults so callers never need to guard against nil structs.
    func parse(_ input: String) -> ParsedTaskInput {
        let dueDate  = extractDate(from: input)
        let priority = extractPriority(from: input)
        let notes    = extractNotes(from: input)
        let title    = buildTitle(from: input, date: dueDate, notes: notes)
        return ParsedTaskInput(title: title, dueDate: dueDate, priority: priority, notes: notes)
    }

    // MARK: - Private Extraction Helpers

    /// Returns the first calendar date found in the text using `NSDataDetector`.
    ///
    /// `NSDataDetector` handles relative expressions like "tomorrow" and
    /// "next week" in addition to absolute dates, making it well-suited for
    /// natural-language task input without a custom NLP grammar.
    ///
    /// - Parameter text: The text to search.
    /// - Returns: The detected `Date`, or `nil` if no date expression was found.
    private func extractDate(from text: String) -> Date? {
        let range = NSRange(text.startIndex..., in: text)
        return dateDetector?.firstMatch(in: text, range: range)?.date
    }

    /// Infers a `Priority` level by matching priority-signal keywords in the text.
    ///
    /// The matching is case-insensitive and checked in descending priority order
    /// so that "urgent" always wins over "important" when both appear.
    ///
    /// - Parameter text: The text to scan for priority signals.
    /// - Returns: The highest matching `Priority`, or `.none` if no keywords matched.
    private func extractPriority(from text: String) -> Priority {
        let lower = text.lowercased()
        // High-priority signals: words conveying immediate urgency.
        if lower.contains("urgent") || lower.contains("asap") || lower.contains("critical") { return .high }
        // Medium-priority signals: words conveying importance but not immediate crisis.
        if lower.contains("important") || lower.contains("high priority") || lower.contains("must") || lower.contains("need to") { return .medium }
        // Low-priority signals: words conveying deferred or optional work.
        if lower.contains("low priority") || lower.contains("whenever") || lower.contains("someday") || lower.contains("no rush") || lower.contains("eventually") { return .low }
        return .none
    }

    /// Extracts supplementary notes text that follows a recognized connector word.
    ///
    /// Connector words like "regarding" and "notes:" signal that the text after
    /// them is supporting context rather than part of the task title.
    ///
    /// - Parameter text: The text to search for a notes segment.
    /// - Returns: The text following the first matched connector, or `""` if none found.
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

    /// Builds the cleaned task title by removing date strings, priority keywords,
    /// speech filler prefixes, and the notes segment from the raw input.
    ///
    /// The title is constructed from the input rather than from extracted fields
    /// so that the removal operations can be applied to the original character
    /// positions without index invalidation across multiple passes.
    ///
    /// - Parameters:
    ///   - text: The original raw input string.
    ///   - date: The extracted date value, used to find and remove the date substring.
    ///   - notes: The extracted notes text, used to find and remove the notes segment.
    /// - Returns: A cleaned title string. Falls back to the full original input if
    ///   the cleaning process produces an empty string.
    private func buildTitle(from text: String, date: Date?, notes: String) -> String {
        var result = text

        // Remove notes segment from the connector word onward
        if !notes.isEmpty {
            let connectors = ["to discuss", "regarding", "concerning", "notes:", "note:", "about"]
            let lower = result.lowercased()
            for connector in connectors {
                if let range = lower.range(of: connector) {
                    // Compute the character offset in the original (non-lowercased) string
                    // because String indices are not interchangeable between different String instances.
                    let offset = result.distance(from: result.startIndex, to: range.lowerBound)
                    let idx = result.index(result.startIndex, offsetBy: offset)
                    result = String(result[..<idx])
                    break
                }
            }
        }

        // Remove detected date string using the same detector to find its exact range.
        if date != nil {
            let range = NSRange(result.startIndex..., in: result)
            if let match = dateDetector?.firstMatch(in: result, range: range),
               let swiftRange = Range(match.range, in: result) {
                result = result.replacingCharacters(in: swiftRange, with: "")
            }
        }

        // Remove priority keywords so they do not appear in the title.
        let priorityMarkers = ["urgent", "asap", "critical", "high priority", "important",
                               "must", "need to", "low priority", "whenever", "someday",
                               "no rush", "eventually"]
        for marker in priorityMarkers {
            result = result.replacingOccurrences(of: marker, with: "", options: .caseInsensitive)
        }

        // Remove common speech filler prefixes produced by voice dictation.
        let fillers = ["remind me to", "remind me", "add task", "task:", "todo:", "to do:"]
        var lower = result.lowercased().trimmingCharacters(in: .whitespaces)
        for filler in fillers {
            if lower.hasPrefix(filler) {
                result = String(result.dropFirst(filler.count))
                // Re-lowercase the trimmed result to check the next filler on a clean string.
                lower = result.lowercased().trimmingCharacters(in: .whitespaces)
            }
        }

        // Collapse multiple spaces introduced by keyword removal, then trim.
        let clean = result
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Guard against an entirely-removed input by falling back to the original text.
        return clean.isEmpty ? text : clean
    }
}
