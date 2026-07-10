// CodeRingComplication.swift — OPTIONAL watch-face complication (WidgetKit).
// Accessory circular launcher: tap → codering://new → straight into setup.
// Lives in its own Widget Extension target — see BUILD_MANUAL.md step 7.
// This file intentionally has no CodeCore dependency.

import WidgetKit
import SwiftUI

struct LaunchEntry: TimelineEntry {
    let date: Date = Date()
}

struct LaunchProvider: TimelineProvider {
    func placeholder(in context: Context) -> LaunchEntry { LaunchEntry() }

    func getSnapshot(in context: Context, completion: @escaping (LaunchEntry) -> Void) {
        completion(LaunchEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LaunchEntry>) -> Void) {
        completion(Timeline(entries: [LaunchEntry()], policy: .never))
    }
}

struct ComplicationView: View {
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "bolt.heart.fill")
                .font(.system(size: 20, weight: .bold))
        }
        .widgetURL(URL(string: "codering://new"))
        .containerBackground(for: .widget) { Color.clear }
    }
}

@main
struct CodeRingComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CodeRingLaunch", provider: LaunchProvider()) { _ in
            ComplicationView()
        }
        .configurationDisplayName("CodeRing")
        .description("Start a code instantly.")
        .supportedFamilies([.accessoryCircular])
    }
}
