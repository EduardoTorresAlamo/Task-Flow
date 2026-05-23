import Foundation
import NaturalLanguage

/// Structured metadata extracted from a task's text content.
///
/// Used by `CalendarSyncService` to populate `EKEvent` fields beyond
/// the basic title and start/end time.
struct EnrichedEventData {
    /// A location name extracted from the task title or notes, if any.
    var location: String?
    /// A comma-separated list of personal names found in the task text, if any.
    var attendeeNote: String?
    /// The first URL found in the task notes, if any.
    var url: URL?
    /// Estimated event duration in seconds, derived from duration hints in the text.
    /// Defaults to 3600 (1 hour) when no hint is present.
    var durationSeconds: TimeInterval = 3600
    /// A formatted string combining priority, notes, attendees, and URL
    /// for use as the `EKEvent.notes` field.
    var formattedNotes: String
}

/// Extracts structured metadata from a task's free-form text using on-device NLP.
///
/// `IntelligenceEnricher` uses `NLTagger` for named-entity recognition (place
/// names, personal names) and `NSDataDetector` / `NSRegularExpression` for
/// URL and duration extraction. All processing is local with no network calls.
///
/// Designed as a value type (struct) because it is stateless: the same instance
/// can be used concurrently from multiple call sites without synchronisation.
struct IntelligenceEnricher {
    /// Analyses the given task and returns enriched event metadata.
    ///
    /// The enrichment pipeline runs in order:
    /// 1. Named-entity tagging to extract locations and personal names.
    /// 2. Link detection to find the first URL in the task notes.
    /// 3. Regex matching to infer event duration from text like "30 min" or "2 hours".
    /// 4. Note formatting that combines all findings into a single string.
    ///
    /// - Parameter task: The task whose title and notes will be analysed.
    /// - Returns: An `EnrichedEventData` value with all extractable fields populated.
    func enrich(task: Task) -> EnrichedEventData {
        // Combine title and notes so entity recognition has maximum context.
        let combined = task.title + " " + task.notes

        var location: String?
        var attendeeNames: [String] = []

        // Use NLTagger with the .nameType scheme to identify named entities.
        // .omitPunctuation and .omitWhitespace skip non-entity tokens.
        // .joinNames collapses multi-word names (e.g. "John Smith") into a single token.
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = combined
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        tagger.enumerateTags(in: combined.startIndex..<combined.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            switch tag {
            case .placeName:
                // Take only the first place name to populate the EKEvent location field.
                if location == nil { location = String(combined[range]) }
            case .personalName:
                attendeeNames.append(String(combined[range]))
            default:
                break
            }
            return true // Continue enumeration.
        }

        let attendeeNote = attendeeNames.isEmpty ? nil : attendeeNames.joined(separator: ", ")

        // Use NSDataDetector with the .link type to find the first URL in the notes field.
        // Only notes (not title) are searched to avoid false positives from technical terms.
        var extractedURL: URL?
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
           let match = detector.firstMatch(in: task.notes, range: NSRange(task.notes.startIndex..., in: task.notes)),
           let range = Range(match.range, in: task.notes) {
            extractedURL = URL(string: String(task.notes[range]))
        }

        // Regex to detect duration hints like "30 min", "1 hour", "2 hrs".
        // Capture group 1: the numeric value; capture group 2: the time unit.
        var durationSeconds: TimeInterval = 3600
        if let regex = try? NSRegularExpression(pattern: #"(\d+)\s*(min(?:utes?)?|hr?s?|hours?)"#, options: .caseInsensitive),
           let match = regex.firstMatch(in: combined, range: NSRange(combined.startIndex..., in: combined)),
           let numRange = Range(match.range(at: 1), in: combined),
           let unitRange = Range(match.range(at: 2), in: combined),
           let number = Int(combined[numRange]) {
            let unit = combined[unitRange].lowercased()
            if unit.hasPrefix("min") {
                // Convert minutes to seconds.
                durationSeconds = TimeInterval(number * 60)
            } else {
                // All other matched units ("hr", "hrs", "hour", "hours") are in hours.
                durationSeconds = TimeInterval(number * 3600)
            }
        }

        // Build the EKEvent notes string by layering priority, task notes,
        // attendee list, and URL on separate lines for readability in Calendar.app.
        var formattedNotes = "[\(task.priority.label)]"
        if !task.notes.isEmpty { formattedNotes += " \(task.notes)" }
        if let a = attendeeNote { formattedNotes += "\nWith: \(a)" }
        if let u = extractedURL { formattedNotes += "\n\(u.absoluteString)" }

        return EnrichedEventData(
            location: location,
            attendeeNote: attendeeNote,
            url: extractedURL,
            durationSeconds: durationSeconds,
            formattedNotes: formattedNotes
        )
    }
}
