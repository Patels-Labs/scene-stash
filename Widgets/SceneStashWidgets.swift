import SwiftUI
import WidgetKit
#if !targetEnvironment(macCatalyst)
import ActivityKit
import AppIntents
#endif

// Widgets and Live Activities can only be built in SwiftUI; the app itself stays UIKit.

@main
struct SceneStashWidgets: WidgetBundle {
    var body: some Widget {
        TonightWidget()
        PremiereWidget()
        UpNextWidget()
        #if !targetEnvironment(macCatalyst)
        NowShowingLiveActivity()
        #endif
    }
}

// MARK: - Shared look

extension Color {
    init(hex: String) {
        let v = UInt64(hex, radix: 16) ?? 0xF5B544
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// A saved poster filling the widget, or the title's colour when there's no poster on disk, shaded for white type.
private struct Art: View {
    let id: Int?
    var tint: String? = nil

    var body: some View {
        Group {
            if let id, let url = SharedBox.posterURL(id), let image = UIImage(contentsOfFile: url.path) {
                Color.clear.overlay(Image(uiImage: image).resizable().scaledToFill()).clipped()
            } else {
                tint.map { Color(hex: $0) } ?? Color.black
            }
        }
        .overlay(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom))
    }
}

/// A widget with nothing to show, or locked: a small label over a bold line.
private struct Message: View {
    let label: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            Text(title).font(.system(.headline, weight: .bold)).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}

nonisolated struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

nonisolated struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .sample : WidgetSnapshot.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // The app reloads timelines whenever Tonight refreshes; tick every 15 minutes so countdowns stay honest.
        let now = Date.now
        let entries = (0..<8).map { SnapshotEntry(date: now.addingTimeInterval(Double($0) * 900), snapshot: WidgetSnapshot.load()) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

nonisolated extension WidgetSnapshot {
    static var sample: WidgetSnapshot {
        var s = WidgetSnapshot()
        s.unlocked = true
        s.doors = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: .now)
        s.booked = 102
        s.programme = [
            .init(id: 1, name: "Severance", code: "S2 E4", start: s.doors ?? .now, tint: "2A8C9C"),
            .init(id: 2, name: "Dune: Part Two", code: "72m left", start: (s.doors ?? .now).addingTimeInterval(52 * 60), tint: "B5762C"),
        ]
        s.premiere = .init(id: 3, name: "The Bear", label: "Season 5 premiere", date: .now.addingTimeInterval(4 * 86400))
        s.card = .init(id: 1, name: "Severance", season: 2, holes: [1, 1, 1, 2, 0, 0, 0, 0, 0, 0], left: 6)
        return s
    }
}

// MARK: - Tonight

struct TonightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "tonight", provider: SnapshotProvider()) { entry in
            let first = entry.snapshot.unlocked ? entry.snapshot.programme.first : nil
            TonightView(snapshot: entry.snapshot).containerBackground(for: .widget) { Art(id: first?.id, tint: first?.tint) }
        }
        .configurationDisplayName("Tonight")
        .description("What's on tonight, and when.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct TonightView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if !snapshot.unlocked { Message(label: "All-Access Pass", title: "Unlock in Scene Stash") } else if let first = snapshot.programme.first {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Tonight" + (snapshot.doors.map { " · From " + $0.formatted(date: .omitted, time: .shortened) } ?? ""))
                    Spacer(minLength: 4)
                    Text("\(snapshot.booked / 60)h \(snapshot.booked % 60)m")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                Spacer(minLength: 0)
                Text(first.name).font(.system(.title2, weight: .bold)).lineLimit(1)
                Text(first.start.formatted(date: .omitted, time: .shortened) + " · " + first.code).font(.subheadline).lineLimit(1)
                ForEach(Array(snapshot.programme.prefix(family == .systemLarge ? 4 : 2).dropFirst().enumerated()), id: \.offset) { _, slot in
                    HStack {
                        Text(slot.name).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(slot.start.formatted(date: .omitted, time: .shortened)).foregroundStyle(.white.opacity(0.75))
                    }
                    .font(.footnote)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            Message(label: "Tonight", title: "Nothing on yet")
        }
    }
}

// MARK: - Premiere countdown

struct PremiereWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "premiere", provider: SnapshotProvider()) { entry in
            PremiereView(snapshot: entry.snapshot, now: entry.date)
                .containerBackground(for: .widget) { Art(id: entry.snapshot.unlocked ? entry.snapshot.premiere?.id : nil) }
        }
        .configurationDisplayName("Coming soon")
        .description("Days until the next new episode or season in your library.")
        .supportedFamilies([.systemSmall])
    }
}

private struct PremiereView: View {
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        if !snapshot.unlocked { Message(label: "All-Access Pass", title: "Unlock in Scene Stash") } else if let p = snapshot.premiere {
            let days = max(Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now), to: p.date).day ?? 0, 0)
            VStack(alignment: .leading, spacing: 1) {
                Text(days == 0 ? "Out today" : days == 1 ? "In 1 day" : "In \(days) days").font(.caption.weight(.semibold))
                Text(p.name).font(.system(.headline, weight: .bold)).lineLimit(2)
                Text(p.label).font(.caption2).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        } else {
            Message(label: "Coming soon", title: "Nothing announced")
        }
    }
}

// MARK: - Up Next

struct UpNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "punchcard", provider: SnapshotProvider()) { entry in
            UpNextView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { Art(id: entry.snapshot.unlocked ? entry.snapshot.card?.id : nil) }
        }
        .configurationDisplayName("Up Next")
        .description("The season you're on, episode by episode.")
        .supportedFamilies([.systemSmall])
    }
}

private struct UpNextView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        if !snapshot.unlocked { Message(label: "All-Access Pass", title: "Unlock in Scene Stash") } else if let card = snapshot.card {
            let watched = card.holes.filter { $0 == 1 }.count
            VStack(alignment: .leading, spacing: 4) {
                Text(card.name).font(.system(.headline, weight: .bold)).lineLimit(2)
                Text("Season \(card.season) · " + (card.left == 0 ? "Caught up" : "\(card.left) left")).font(.caption2).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                ProgressView(value: Double(watched), total: Double(max(card.holes.count, 1)))
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .accessibilityLabel("\(watched) of \(card.holes.count) episodes watched")
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        } else {
            Message(label: "Up Next", title: "Start a show")
        }
    }
}

// MARK: - Now showing (Live Activity)

#if !targetEnvironment(macCatalyst)
struct NowShowingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowShowingAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let a = context.attributes, s = context.state, tint = Color(hex: a.tint)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Poster(id: a.id, tint: tint).frame(width: 36, height: 54) }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.pausedAt == nil ? a.name : "Paused").font(.system(.headline, weight: .bold)).lineLimit(1)
                        Status(attributes: a, state: s).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) { Controls(state: s, tint: tint) }
                DynamicIslandExpandedRegion(.bottom) { TimeBar(attributes: a, state: s, tint: tint) }
            } compactLeading: {
                Poster(id: a.id, tint: tint).frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 6))
            } compactTrailing: {
                if s.finished { Image(systemName: "checkmark").foregroundStyle(tint) }
                else if s.pausedAt != nil { Image(systemName: "pause.fill").foregroundStyle(tint) }
                else { Text(timerInterval: Date.now...max(a.end(s), .now), countsDown: true).font(.system(.caption, weight: .semibold)).foregroundStyle(tint).frame(maxWidth: 52).monospacedDigit() }
            } minimal: {
                Circle().fill(tint).frame(width: 12, height: 12)
            }
        }
    }
}

private struct LockScreenView: View {
    let attributes: NowShowingAttributes
    let state: NowShowingAttributes.ContentState

    var body: some View {
        let tint = Color(hex: attributes.tint)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Poster(id: attributes.id, tint: tint).frame(width: 44, height: 66)
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.finished ? "Finished" : state.pausedAt == nil ? "Now Showing" : "Paused").font(.caption.weight(.semibold)).foregroundStyle(tint).lineLimit(1)
                    Text(attributes.name).font(.system(.title3, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                    Status(attributes: attributes, state: state).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 0)
                Controls(state: state, tint: tint)
            }
            TimeBar(attributes: attributes, state: state, tint: tint)
            if attributes.stinger, !state.finished {
                HStack(spacing: 8) {
                    Text("After the credits").font(.caption.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                    Text("There's a scene during or after the credits.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

/// "Ends 21:54 · 1:12:03 left", or the paused position.
private struct Status: View {
    let attributes: NowShowingAttributes
    let state: NowShowingAttributes.ContentState

    var body: some View {
        if state.finished {
            Text("Marked as watched. Rate it in Scene Stash.")
        } else if state.pausedAt != nil {
            let s = Int(state.elapsed())
            Text(String(format: "At %d:%02d:%02d · end time moves with you", s / 3600, s % 3600 / 60, s % 60))
        } else {
            let end = attributes.end(state)
            if end > .now {
                Text("Ends \(end.formatted(date: .omitted, time: .shortened)) · \(Text(timerInterval: Date.now...end, countsDown: true)) left")
            } else {
                Text("Credits rolling")
            }
        }
    }
}

private struct Controls: View {
    let state: NowShowingAttributes.ContentState
    let tint: Color

    var body: some View {
        if !state.finished {
            HStack(spacing: 8) {
                if state.pausedAt == nil {
                    Button(intent: PauseWatchingIntent()) { Image(systemName: "pause.fill").frame(width: 40, height: 40) }
                        .tint(.white.opacity(0.2)).foregroundStyle(.white)
                        .accessibilityLabel("Pause")
                } else {
                    Button(intent: ResumeWatchingIntent()) { Image(systemName: "play.fill").frame(width: 40, height: 40) }
                        .tint(.white).foregroundStyle(.black)
                        .accessibilityLabel("Resume")
                }
                Button(intent: FinishWatchingIntent()) { Image(systemName: "checkmark").frame(width: 40, height: 40) }
                    .tint(tint).foregroundStyle(.black)
                    .accessibilityLabel("Mark finished")
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
        }
    }
}

/// How far through you are, in the poster's colour; it runs itself while playing.
private struct TimeBar: View {
    let attributes: NowShowingAttributes
    let state: NowShowingAttributes.ContentState
    let tint: Color

    var body: some View {
        let total = TimeInterval(attributes.runtimeMinutes * 60)
        Group {
            if state.pausedAt == nil, !state.finished, attributes.end(state) > .now {
                ProgressView(timerInterval: state.startedAt...attributes.end(state), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
            } else {
                ProgressView(value: state.finished ? 1 : min(max(state.elapsed() / total, 0), 1))
            }
        }
        .progressViewStyle(.linear)
        .tint(tint)
    }
}

private struct Poster: View {
    let id: Int
    let tint: Color

    var body: some View {
        if let url = SharedBox.posterURL(id), let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().aspectRatio(contentMode: .fill).clipShape(RoundedRectangle(cornerRadius: 7))
        } else {
            RoundedRectangle(cornerRadius: 7).fill(LinearGradient(colors: [tint, tint.opacity(0.3)], startPoint: .top, endPoint: .bottom))
        }
    }
}
#endif
