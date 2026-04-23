import Foundation
import NaturalLanguage

struct EnrichedEventData {
    var location: String?
    var attendeeNote: String?
    var url: URL?
    var durationSeconds: TimeInterval = 3600
    var formattedNotes: String
}

struct IntelligenceEnricher {
    func enrich(task: Task) -> EnrichedEventData {
        let combined = task.title + " " + task.notes

        var location: String?
        var attendeeNames: [String] = []

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = combined
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        tagger.enumerateTags(in: combined.startIndex..<combined.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            switch tag {
            case .placeName:
                if location == nil { location = String(combined[range]) }
            case .personalName:
                attendeeNames.append(String(combined[range]))
            default:
                break
            }
            return true
        }

        let attendeeNote = attendeeNames.isEmpty ? nil : attendeeNames.joined(separator: ", ")

        var extractedURL: URL?
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
           let match = detector.firstMatch(in: task.notes, range: NSRange(task.notes.startIndex..., in: task.notes)),
           let range = Range(match.range, in: task.notes) {
            extractedURL = URL(string: String(task.notes[range]))
        }

        var durationSeconds: TimeInterval = 3600
        if let regex = try? NSRegularExpression(pattern: #"(\d+)\s*(min(?:utes?)?|hr?s?|hours?)"#, options: .caseInsensitive),
           let match = regex.firstMatch(in: combined, range: NSRange(combined.startIndex..., in: combined)),
           let numRange = Range(match.range(at: 1), in: combined),
           let unitRange = Range(match.range(at: 2), in: combined),
           let number = Int(combined[numRange]) {
            let unit = combined[unitRange].lowercased()
            if unit.hasPrefix("min") {
                durationSeconds = TimeInterval(number * 60)
            } else {
                durationSeconds = TimeInterval(number * 3600)
            }
        }

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
