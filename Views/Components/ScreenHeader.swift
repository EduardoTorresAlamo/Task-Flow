import SwiftUI

/// The large title block at the top of a top-level screen.
///
/// Renders the 34pt screen name, an optional one-line subtitle, and an optional
/// hand-drawn accent squiggle. The squiggle is the design's signature mark: a
/// wave echoing the app icon, drawn only on screens that have a subtitle-worthy
/// sense of "flow" (Inbox), and omitted on the quieter archive screens.
struct ScreenHeader: View {
    /// The screen name, e.g. "Inbox".
    let title: String

    /// A short status line under the title, e.g. "4 tasks pending".
    /// Pass `nil` to omit the line entirely rather than reserving its height.
    var subtitle: String? = nil

    /// Whether to draw the accent wave under the title.
    var showsWave: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.tfScreenTitle)
                // The design tightens the 34pt title by 0.3pt so the large
                // glyphs do not read as loose next to the 13pt subtitle.
                .tracking(-0.3)
                .foregroundStyle(Theme.text)

            if let subtitle {
                Text(subtitle)
                    .font(.tfSubtitle)
                    .foregroundStyle(Theme.textSecondary)
            }

            if showsWave {
                WaveAccent()
                    .frame(width: 100, height: 12)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.titleInset)
        .padding(.bottom, 16)
    }
}

/// The accent squiggle drawn under the Inbox title.
///
/// Four half-period bumps across the full width, stroked in the accent at 55%
/// so it reads as a flourish rather than a divider.
struct WaveAccent: View {
    var body: some View {
        // Drawn with GeometryReader-free relative math: Path receives the
        // resolved rect, so the shape scales to whatever frame the caller sets.
        WaveShape()
            .stroke(
                Theme.accent.opacity(0.55),
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
            )
    }
}

/// A four-bump sine-like wave built from quadratic segments.
///
/// Mirrors the design's `M0 7 Q12 0 25 7 T50 7 T75 7 T100 7` path: an initial
/// quadratic curve followed by three smooth reflections of it.
private struct WaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        // One bump spans a quarter of the width; its control point sits at the
        // top of the rect, half a bump in.
        let bump = rect.width / 4
        path.move(to: CGPoint(x: rect.minX, y: midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + bump, y: midY),
            control: CGPoint(x: rect.minX + bump * 0.48, y: rect.minY)
        )
        // addQuadCurve has no "smooth" variant, so each reflected segment
        // repeats the same control offset, which is what T produces here
        // because every bump returns to the same baseline.
        for step in 1..<4 {
            let startX = rect.minX + bump * CGFloat(step)
            path.addQuadCurve(
                to: CGPoint(x: startX + bump, y: midY),
                control: CGPoint(x: startX + bump * 0.48, y: rect.minY)
            )
        }
        return path
    }
}

/// The uppercase label that introduces a group of rows ("TODAY", "LATER").
///
/// 11pt semibold with wide tracking, in the tertiary text color, inset by 4pt
/// from the cards below it so the label's stem aligns with the card text
/// rather than the card edge.
struct SectionHeader: View {
    /// The label text. Uppercased by the view, so callers pass natural casing.
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.tfSectionLabel)
            .tracking(0.88) // 0.08em at 11pt
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
            .padding(.bottom, 8)
    }
}
