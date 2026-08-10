import SwiftUI

/// The Task-Flow design system: the Nocturne palette and the "Airy Grouped"
/// metrics, expressed once so every screen and the widget extension read the
/// same values.
///
/// This file is compiled into both the app and the widget target (both list
/// `Extensions` in their sources), which is why it holds nothing that depends
/// on SwiftData or on the app's view layer.
///
/// The colors are fixed rather than adaptive: Task-Flow is dark-mode-only and
/// forces `.preferredColorScheme(.dark)` at the root, so a light variant would
/// never be rendered.
enum Theme {

    // MARK: - Palette

    /// Pure black screen ground. The design is dark-mode-first and deliberately
    /// uses true black rather than a dark grey so OLED displays render the
    /// background as unlit pixels.
    static let background = Color.black

    /// The slightly-lifted ground used behind widgets, where true black would
    /// disappear into the Home Screen wallpaper instead of reading as a surface.
    static let widgetBackground = Color(hex: "#0C0C10")

    /// Primary text. Very slightly warm off-white; pure white reads as harsh
    /// against a true-black ground at this type size.
    static let text = Color(hex: "#F0F0F2")

    /// Secondary text: due times, counts, metadata. 55% of `text`.
    static let textSecondary = Color(hex: "#F0F0F2").opacity(0.55)

    /// Tertiary text: section labels, placeholders, disabled affordances.
    /// 32% of `text`.
    static let textTertiary = Color(hex: "#F0F0F2").opacity(0.32)

    /// Card fill, layered on top of `.ultraThinMaterial` to keep the frosted
    /// blur while lifting the surface off the black ground.
    static let cardFill = Color.white.opacity(0.055)

    /// The hairline edge that separates a card from the ground. At 9% it reads
    /// as a defined edge without becoming a visible outline.
    static let cardBorder = Color.white.opacity(0.09)

    /// The product accent: Nocturne blurple. Replaces the earlier `#6E56CF`
    /// indigo across every interactive control, selection state, and glyph.
    static let accent = Color(hex: "#9184D9")

    /// Priority: low.
    static let blue = Color(hex: "#4D8FE0")
    /// Priority: medium.
    static let orange = Color(hex: "#F0993D")
    /// Priority: high, and the destructive Delete action.
    static let red = Color(hex: "#F0554D")
    /// Accent variant used for project swatches and the fourth series color.
    static let teal = Color(hex: "#5FBF8F")
    /// The swipe-to-complete backdrop.
    static let green = Color(hex: "#4FBF7A")

    /// A warm secondary used only in widget background blooms, never for text.
    static let bloomWarm = Color(hex: "#EF9D6D")

    /// The color choices offered when creating or editing a project, as hex
    /// strings because `Project.colorHex` is persisted as a `String`.
    static let projectPalette = [
        "#9184D9", "#4D8FE0", "#5FBF8F", "#F0993D", "#F0554D", "#A7A1DB"
    ]

    // MARK: - Metrics

    /// Horizontal inset for large screen titles.
    static let titleInset: CGFloat = 22
    /// Horizontal inset for scrolling content. Slightly tighter than the title
    /// so the cards' rounded corners optically align with the title's stem.
    static let contentInset: CGFloat = 18

    /// Corner radius for task cards, edit-form fields, and the Done rows.
    static let cardRadius: CGFloat = 18
    /// Corner radius for the natural-language input bar and project cards,
    /// which sit at a higher level in the hierarchy than a task row.
    static let barRadius: CGFloat = 20
    /// Interior padding for a card.
    static let cardPadding: CGFloat = 16

    /// Gap between cards inside one section.
    static let rowGap: CGFloat = 10
    /// Gap between sections. The "airy" in Airy Grouped is mostly this number.
    static let sectionGap: CGFloat = 22

    /// Distance the row travels before the swipe-to-complete action commits.
    static let swipeCommitDistance: CGFloat = 104
}

// MARK: - Priority colors

extension Priority {
    /// The badge color for this priority level.
    ///
    /// Declared here rather than on the enum itself so `Priority` stays a
    /// Foundation-only type with no SwiftUI dependency, and so the palette
    /// lives in exactly one place.
    var color: Color {
        switch self {
        case .none:   return Theme.textTertiary
        case .low:    return Theme.blue
        case .medium: return Theme.orange
        case .high:   return Theme.red
        }
    }
}

// MARK: - Type scale

extension Font {
    /// 34pt bold: the large screen title (Inbox, Done, Projects).
    static let tfScreenTitle = Font.system(size: 34, weight: .bold)
    /// 22pt bold: the inline title of a modal sheet.
    static let tfSheetTitle = Font.system(size: 22, weight: .bold)
    /// 16pt medium: a task title.
    static let tfRowTitle = Font.system(size: 16, weight: .medium)
    /// 15.5pt semibold: a project name on its card.
    static let tfCardTitle = Font.system(size: 15.5, weight: .semibold)
    /// 13pt regular: the screen subtitle under a large title.
    static let tfSubtitle = Font.system(size: 13)
    /// 12.5pt regular: due times and completion timestamps.
    static let tfMeta = Font.system(size: 12.5)
    /// 11pt semibold: an uppercase section label.
    static let tfSectionLabel = Font.system(size: 11, weight: .semibold)
    /// 10.5pt semibold: the text inside a priority badge.
    static let tfBadge = Font.system(size: 10.5, weight: .semibold)
    /// 15.5pt regular: a form row's leading label.
    static let tfFormRow = Font.system(size: 15.5)
    /// 16pt regular: editable field text.
    static let tfFieldValue = Font.system(size: 16)
}
