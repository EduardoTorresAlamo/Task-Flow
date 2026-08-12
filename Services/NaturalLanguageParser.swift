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
    /// The recurrence rule inferred from repetition phrases, or `nil` if none.
    var recurrence: RecurrenceRule?
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
        let dueDate    = extractDate(from: input)
        let priority   = extractPriority(from: input)
        let notes      = extractNotes(from: input)
        let recurrence = extractRecurrence(from: input, dueDate: dueDate)
        let title      = buildTitle(from: input, date: dueDate, notes: notes)
        return ParsedTaskInput(title: title, dueDate: dueDate, priority: priority, notes: notes, recurrence: recurrence)
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
        // Every keyword is matched on word boundaries via regex, never `contains`:
        // a substring test fires "critical" on "critically", "must" on "mustard",
        // and "someday" on "somedays". The patterns are compiled once as static
        // properties (see `*PriorityPattern`) and checked in descending order so
        // "urgent" wins over "important" when both appear.
        if lower.range(of: Self.highPriorityPattern, options: .regularExpression) != nil { return .high }
        if lower.range(of: Self.mediumPriorityPattern, options: .regularExpression) != nil { return .medium }
        if lower.range(of: Self.lowPriorityPattern, options: .regularExpression) != nil { return .low }
        return .none
    }

    /// Word-boundary regex patterns for each priority level, grouped so a single
    /// `range(of:options:)` call tests every keyword at that level. Kept as
    /// class-level `static let` so the pattern strings are declared once rather
    /// than rebuilt on every parse. `\b` on both sides is what makes the match
    /// whole-word: "no rush" matches "no rush" but "asap" does not match inside
    /// a longer token.
    private static let highPriorityPattern   = #"\b(?:urgent|asap|critical|high priority)\b"#
    private static let mediumPriorityPattern = #"\b(?:important|must|need to)\b"#
    private static let lowPriorityPattern    = #"\b(?:low priority|whenever|someday|no rush|eventually)\b"#

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

    /// Detects a recurrence rule from repetition phrases in the input.
    ///
    /// Matching runs from most specific to least specific so that, for example,
    /// "every 2 weeks" is read as biweekly rather than falling through to the
    /// generic weekly branch. Phrases with no repetition signal (e.g.
    /// "call dentist tomorrow urgent") return `nil`.
    ///
    /// Where a frequency needs an anchor (the weekday for weekly rules, the
    /// day-of-month for monthly rules) it is derived from `dueDate` when one was
    /// detected, falling back to Monday / the 1st.
    ///
    /// - Parameters:
    ///   - text: The raw user input.
    ///   - dueDate: The date extracted from the same input, used to anchor
    ///     weekly and monthly rules.
    /// - Returns: The inferred `RecurrenceRule`, or `nil` if no recurrence phrase matched.
    private func extractRecurrence(from text: String, dueDate: Date?) -> RecurrenceRule? {
        let lower = text.lowercased()

        // "every N days / weeks / months" -- numeric interval, checked first.
        if let rule = extractNumericInterval(from: lower, dueDate: dueDate) { return rule }

        // A specific weekday, e.g. "every monday". Word-boundary matched so
        // "every sun" does not fire "sunday".
        for day in Weekday.allCases where Self.containsWord("every \(day.label.lowercased())", in: lower) {
            return RecurrenceRule(frequency: .weekly(day: day))
        }

        // Every keyword below is word-boundary matched via `containsWord`, never
        // `contains`: a substring test fires "weekly" inside "biweekly" and
        // "daily" inside "dailymotion". Order still runs most- to least-specific.
        if Self.containsWord("every weekday", in: lower) || Self.containsWord("weekdays", in: lower) {
            return RecurrenceRule(frequency: .weekdays)
        }
        if Self.containsWord("biweekly", in: lower) || Self.containsWord("fortnight", in: lower) || Self.containsWord("every other week", in: lower) {
            return RecurrenceRule(frequency: .biweekly(day: anchorWeekday(dueDate)))
        }
        if Self.containsWord("every day", in: lower) || Self.containsWord("daily", in: lower) || Self.containsWord("everyday", in: lower) {
            return RecurrenceRule(frequency: .daily)
        }
        if Self.containsWord("every week", in: lower) || Self.containsWord("weekly", in: lower) {
            return RecurrenceRule(frequency: .weekly(day: anchorWeekday(dueDate)))
        }
        if Self.containsWord("every month", in: lower) || Self.containsWord("monthly", in: lower) {
            return RecurrenceRule(frequency: .monthly(day: anchorDayOfMonth(dueDate)))
        }
        if Self.containsWord("every year", in: lower) || Self.containsWord("yearly", in: lower) || Self.containsWord("annually", in: lower) {
            return RecurrenceRule(frequency: .yearly)
        }
        return nil
    }

    /// True when `keyword` occurs in `text` delimited by word boundaries,
    /// case-insensitively. This is the whole-word counterpart of `contains`:
    /// `containsWord("weekly", in: "biweekly")` is `false`. `keyword` is
    /// regex-escaped so a phrase with metacharacters cannot alter the pattern,
    /// mirroring `removingWholeWord`.
    private static func containsWord(_ keyword: String, in text: String) -> Bool {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: keyword) + "\\b"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Parses an explicit numeric interval such as "every 2 days" or
    /// "every 3 weeks" into a rule, or returns `nil` if no such phrase is present.
    ///
    /// An interval of 2 weeks is normalised to the dedicated `.biweekly`
    /// frequency so it round-trips consistently with keyword detection.
    private func extractNumericInterval(from lower: String, dueDate: Date?) -> RecurrenceRule? {
        guard let regex = try? NSRegularExpression(pattern: #"every\s+(\d+)\s+(day|week|month|year)s?"#),
              let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              let numberRange = Range(match.range(at: 1), in: lower),
              let unitRange = Range(match.range(at: 2), in: lower),
              let interval = Int(lower[numberRange])
        else { return nil }

        let unit = String(lower[unitRange])
        switch unit {
        case "day":
            return RecurrenceRule(frequency: .daily, interval: interval)
        case "week":
            if interval == 2 { return RecurrenceRule(frequency: .biweekly(day: anchorWeekday(dueDate))) }
            return RecurrenceRule(frequency: .weekly(day: anchorWeekday(dueDate)), interval: interval)
        case "month":
            return RecurrenceRule(frequency: .monthly(day: anchorDayOfMonth(dueDate)), interval: interval)
        case "year":
            return RecurrenceRule(frequency: .yearly, interval: interval)
        default:
            return nil
        }
    }

    /// The weekday to anchor a weekly/biweekly rule to: the due date's weekday
    /// when a date was detected, otherwise Monday.
    private func anchorWeekday(_ dueDate: Date?) -> Weekday {
        guard let dueDate else { return .monday }
        return Weekday.from(dueDate)
    }

    /// The day-of-month to anchor a monthly rule to: the due date's day when a
    /// date was detected, otherwise the 1st.
    private func anchorDayOfMonth(_ dueDate: Date?) -> Int {
        guard let dueDate else { return 1 }
        return Calendar.current.component(.day, from: dueDate)
    }

    /// Recurrence phrases stripped from the title so they do not appear in it.
    ///
    /// The numeric "every N units" form is removed separately via regex in
    /// `buildTitle`; this list covers the keyword forms.
    private static let recurrenceMarkers: [String] = [
        "every weekday", "every other week", "every day", "every week",
        "every month", "every year",
        "every monday", "every tuesday", "every wednesday", "every thursday",
        "every friday", "every saturday", "every sunday",
        "weekdays", "biweekly", "fortnightly", "fortnight", "everyday",
        "daily", "weekly", "monthly", "yearly", "annually"
    ]

    /// Removes every whole-word occurrence of `marker` from `text`, case-insensitively.
    ///
    /// The marker is matched only when it is delimited by word boundaries, so
    /// stripping "must" leaves "mustard" untouched. `marker` is regex-escaped
    /// before use so a phrase containing regex metacharacters cannot change the
    /// pattern's meaning. If the pattern somehow fails to compile the original
    /// text is returned unchanged rather than corrupted.
    private static func removingWholeWord(_ marker: String, from text: String) -> String {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: marker) + "\\b"
        return text.replacingOccurrences(
            of: pattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
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
        // Matched on word boundaries (\b): a plain substring replace turned
        // "mustard" into "ard" (it contains "must") and "critically" into
        // "ly". `\b<escaped>\b` only strips the keyword when it stands alone.
        let priorityMarkers = ["urgent", "asap", "critical", "high priority", "important",
                               "must", "need to", "low priority", "whenever", "someday",
                               "no rush", "eventually"]
        for marker in priorityMarkers {
            result = Self.removingWholeWord(marker, from: result)
        }

        // Remove recurrence phrases so they do not leak into the title.
        // The numeric "every N units" form is stripped first via regex, then the
        // keyword forms (longest-first ordering is preserved in the source list).
        result = result.replacingOccurrences(
            of: #"every\s+\d+\s+(day|week|month|year)s?"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        for marker in Self.recurrenceMarkers {
            result = Self.removingWholeWord(marker, from: result)
        }

        // Remove common speech filler prefixes produced by voice dictation.
        // `result` must be trimmed before each prefix check so that
        // `dropFirst(filler.count)` removes exactly the filler characters;
        // checking a trimmed lowercase copy against an untrimmed `result`
        // would drop the wrong characters when leading whitespace is present.
        let fillers = ["remind me to", "remind me", "add task", "task:", "todo:", "to do:"]
        result = result.trimmingCharacters(in: .whitespaces)
        for filler in fillers {
            if result.lowercased().hasPrefix(filler) {
                result = String(result.dropFirst(filler.count))
                    .trimmingCharacters(in: .whitespaces)
            }
        }

        // Collapse runs of whitespace introduced by keyword removal, then trim.
        let clean = result
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Guard against an entirely-removed input by falling back to the original text.
        return clean.isEmpty ? text : clean
    }
}
