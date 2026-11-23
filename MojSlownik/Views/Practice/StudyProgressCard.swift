import SwiftUI

/// Practice "Progress" card: learned / learning / new for the selected scope, the review forecast
/// and the hard-words entry point. Counts come from `StudyProgress` (pure, already scoped).
struct StudyProgressCard: View {
    let breakdown: StudyProgress.Breakdown
    let forecast: StudyProgress.Forecast
    let hardWordCount: Int
    let folderID: UUID?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .footnote) private var barHeight: CGFloat = 12
    @ScaledMetric(relativeTo: .footnote) private var dotSize: CGFloat = 8
    @ScaledMetric(relativeTo: .body) private var rowTile: CGFloat = 32

    private var isAX: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Progress")
                .font(.footnote.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(Color.subtleText)
            VStack(spacing: 0) {
                summary
                hairline
                forecastRow
                if hardWordCount > 0 {
                    hairline
                    hardWordsRow
                }
            }
            .cardStyle()
        }
    }

    private var hairline: some View {
        Rectangle().fill(Color.appBorder).frame(height: 1)
    }

    // MARK: Summary

    private var summary: some View {
        VStack(spacing: AppSpacing.s) {
            ProgressSegmentsBar(segments: [
                .init(id: "learned", value: breakdown.learned, color: .appMastery),
                .init(id: "learning", value: breakdown.learning, color: .appLearning),
                .init(id: "new", value: breakdown.new, color: .appRingTrack)
            ], height: barHeight)
            let layout = isAX
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.xs))
                : AnyLayout(HStackLayout(alignment: .top, spacing: AppSpacing.xs))
            layout {
                legend(count: breakdown.learned, color: .appMastery, label: "learned")
                legend(count: breakdown.learning, color: .appLearning, label: "learning")
                legend(count: breakdown.new, color: .appRingTrack, label: "new")
            }
        }
        .padding(AppSpacing.m)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue(String(localized: "learned \(breakdown.learned), learning \(breakdown.learning), new \(breakdown.new) of \(breakdown.total)"))
        .accessibilityIdentifier("studyProgressSummary")
    }

    private func legend(count: Int, color: Color, label: LocalizedStringKey) -> some View {
        let layout = isAX
            ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: AppSpacing.xs))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.xxs))
        return layout {
            Text("\(count)")
                .font(.title2.weight(.heavy))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(Color.appInk)
            HStack(spacing: AppSpacing.xxs + 2) {
                Circle().fill(color).frame(width: dotSize, height: dotSize)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(Color.subtleText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Rows

    private func iconTile(_ name: String, tile: Color, glyph: Color) -> some View {
        Image(systemName: name)
            .font(.body)
            .fontWeight(.medium)
            .foregroundStyle(glyph)
            .frame(width: rowTile, height: rowTile)
            .background(tile, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            .accessibilityHidden(true)
    }

    private var forecastRow: some View {
        let layout = isAX
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: AppSpacing.s))
        return layout {
            iconTile("calendar", tile: .appAccentSoft, glyph: .appInk)
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("Tomorrow \(forecast.tomorrow) · this week \(forecast.week)")
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(Color.appInk)
                Text("Scheduled reviews")
                    .font(.footnote)
                    .foregroundStyle(Color.subtleText)
            }
            if !isAX { Spacer(minLength: 0) }
        }
        .padding(.horizontal, AppSpacing.m)
        .padding(.vertical, AppSpacing.s)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scheduled reviews")
        .accessibilityValue(String(localized: "Tomorrow: \(forecast.tomorrow), this week: \(forecast.week)"))
        .accessibilityIdentifier("studyForecast")
    }

    private var hardWordsRow: some View {
        let layout = isAX
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: AppSpacing.s))
        return NavigationLink {
            FlashcardsView(folderID: folderID, session: .hardWords)
        } label: {
            layout {
                iconTile("exclamationmark.triangle", tile: .appWarningSurface, glyph: .appWarning)
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("Hard words")
                        .font(.body)
                        .foregroundStyle(Color.appInk)
                    Text("Forgotten at least \(StudyProgress.hardWordLapseThreshold) times")
                        .font(.footnote)
                        .foregroundStyle(Color.subtleText)
                        .multilineTextAlignment(.leading)
                }
                if !isAX { Spacer(minLength: 0) }
                HStack(spacing: AppSpacing.xs) {
                    Text("\(hardWordCount)")
                        .font(.body.bold())
                        .monospacedDigit()
                        .foregroundStyle(Color.appInk)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.subtleText)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, AppSpacing.m)
            .padding(.vertical, AppSpacing.s)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hard words")
        .accessibilityValue("\(hardWordCount) words")
        .accessibilityHint("Practice only the hard words")
        .accessibilityIdentifier("hardWordsRow")
    }
}
