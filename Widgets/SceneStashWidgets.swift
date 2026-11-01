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
        PunchCardWidget()
        #if !targetEnvironment(macCatalyst)
        NowShowingLiveActivity()
        #endif
    }
}

// MARK: - Shared look

private let amber = Color(hex: "F5B544")

extension Color {
    init(hex: String) {
        let v = UInt64(hex, radix: 16) ?? 0xF5B544
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

extension Font {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .black).width(.compressed) }
    static func caps(_ size: CGFloat = 9) -> Font { .system(size: size, weight: .bold).width(.expanded) }
}

private struct Caps: View {
    let text: String
    var color: Color = .white.opacity(0.62)
    var size: CGFloat = 9
    var body: some View { Text(text.uppercased()).font(.caps(size)).tracking(1.2).foregroundStyle(color).lineLimit(1) }
}

/// Shown in place of a widget's content until the All-Access Pass is unlocked.
private struct Locked: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Caps(text: "All-Access Pass", color: amber)
            Text("UNLOCK IN SCENE STASH").font(.display(22)).foregroundStyle(.white)
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
            TonightView(snapshot: entry.snapshot).containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Tonight")
        .description("Tonight's programme, on the clock.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct TonightView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if !snapshot.unlocked { Locked() } else if snapshot.programme.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Caps(text: "Tonight")
                Text("NOTHING ON,\nYET.").font(.display(30)).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Caps(text: "Tonight" + (snapshot.doors.map { " · Doors " + $0.formatted(date: .omitted, time: .shortened) } ?? ""))
                    Spacer()
                    Caps(text: "\(snapshot.booked / 60)h \(snapshot.booked % 60)m")
                }
                ForEach(Array(snapshot.programme.prefix(family == .systemLarge ? 4 : 2).enumerated()), id: \.offset) { i, slot in
                    HStack(spacing: 8) {
                        Caps(text: slot.start.formatted(date: .omitted, time: .shortened), color: i == 0 ? Color(hex: "FF5A4E") : .white.opacity(0.5), size: 8)
                            .frame(width: 40, alignment: .leading)
                        HStack {
                            Text(slot.name.uppercased()).font(.display(18)).lineLimit(1)
                            Spacer(minLength: 4)
                            Caps(text: slot.code, color: .white.opacity(0.85), size: 7)
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(LinearGradient(colors: [Color(hex: slot.tint).opacity(0.35), Color(hex: slot.tint)], startPoint: .leading, endPoint: .trailing),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .foregroundStyle(.white)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Premiere countdown

struct PremiereWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "premiere", provider: SnapshotProvider()) { entry in
            PremiereView(snapshot: entry.snapshot, now: entry.date).containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Coming soon")
        .description("Days until the next premiere in your stash.")
        .supportedFamilies([.systemSmall])
    }
}

private struct PremiereView: View {
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        if !snapshot.unlocked { Locked() } else if let p = snapshot.premiere {
            let days = max(Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now), to: p.date).day ?? 0, 0)
            VStack(alignment: .leading, spacing: 0) {
                Caps(text: days == 0 ? "Out today" : "Premieres in")
                Spacer(minLength: 0)
                if days > 0 {
                    Text("\(days)").font(.display(60)).foregroundStyle(.white)
                    Caps(text: days == 1 ? "Day" : "Days", color: .white, size: 8)
                }
                Spacer(minLength: 4)
                Text(p.name.uppercased()).font(.display(20)).foregroundStyle(.white).lineLimit(2)
                Caps(text: p.label, size: 7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Caps(text: "Coming soon")
                Text("NOTHING\nANNOUNCED").font(.display(24)).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }
}

// MARK: - Punch card

struct PunchCardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "punchcard", provider: SnapshotProvider()) { entry in
            PunchCardView(snapshot: entry.snapshot).containerBackground(Color(hex: "0D1416"), for: .widget)
        }
        .configurationDisplayName("Punch card")
        .description("The season you're on, hole by hole.")
        .supportedFamilies([.systemSmall])
    }
}

private struct PunchCardView: View {
    let snapshot: WidgetSnapshot
    private let teal = Color(hex: "8FD4DC")

    var body: some View {
        if !snapshot.unlocked { Locked() } else if let card = snapshot.card {
            VStack(alignment: .leading, spacing: 8) {
                Caps(text: "Punch card · S\(card.season)", color: teal)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 4) {
                    ForEach(Array(card.holes.prefix(20).enumerated()), id: \.offset) { _, hole in
                        Circle()
                            .fill(hole == 1 ? Color.black : hole == 2 ? Color.clear : Color(hex: "22343A"))
                            .overlay(Circle().strokeBorder(hole == 2 ? teal : hole == 1 ? teal.opacity(0.4) : .clear, lineWidth: hole == 2 ? 2 : 1))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
                Spacer(minLength: 0)
                Text(card.name.uppercased()).font(.display(20)).foregroundStyle(.white).lineLimit(1)
                Caps(text: card.left == 0 ? "Caught up" : "\(card.left) left", size: 7)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Caps(text: "Punch card", color: teal)
                Text("START A\nSHOW").font(.display(26)).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
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
                .activityBackgroundTint(Color(red: 0.08, green: 0.06, blue: 0.04).opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let a = context.attributes, s = context.state, tint = Color(hex: a.tint)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Poster(id: a.id, tint: tint).frame(width: 36, height: 54) }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.pausedAt == nil ? a.name.uppercased() : "PAUSED").font(.display(22)).lineLimit(1)
                        Status(attributes: a, state: s).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) { Controls(state: s, tint: tint) }
                DynamicIslandExpandedRegion(.bottom) { Strip(attributes: a, state: s, tint: tint).frame(height: 10) }
            } compactLeading: {
                Poster(id: a.id, tint: tint).frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 6))
            } compactTrailing: {
                if s.finished { Image(systemName: "checkmark").foregroundStyle(tint) }
                else if s.pausedAt != nil { Image(systemName: "pause.fill").foregroundStyle(tint) }
                else { Text(timerInterval: Date.now...max(a.end(s), .now), countsDown: true).font(.display(16)).foregroundStyle(tint).frame(maxWidth: 52).monospacedDigit() }
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
                    Caps(text: state.finished ? "Finished" : state.pausedAt == nil ? "Now showing" : "Paused", color: tint, size: 8)
                    Text(attributes.name.uppercased()).font(.display(28)).foregroundStyle(.white).lineLimit(1)
                    Status(attributes: attributes, state: state).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 0)
                Controls(state: state, tint: tint)
            }
            Strip(attributes: attributes, state: state, tint: tint).frame(height: 16)
            if attributes.stinger, !state.finished {
                HStack(spacing: 8) {
                    Caps(text: "Stay seated", color: amber, size: 7)
                    Text("There's a scene during or after the credits.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
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
            Text("Marked seen. Rate it in Scene Stash.")
        } else if state.pausedAt != nil {
            let s = Int(state.elapsed())
            Text(String(format: "At %d:%02d:%02d · end time moves with you", s / 3600, s % 3600 / 60, s % 60))
        } else {
            let end = attributes.end(state)
            if end > .now {
                Text("Ends \(end.formatted(date: .omitted, time: .shortened)) · ") + Text(timerInterval: Date.now...end, countsDown: true) + Text(" left")
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

/// A sliver of film: frames filling with the poster's colour; it runs itself while playing.
private struct Strip: View {
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
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 4))
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
