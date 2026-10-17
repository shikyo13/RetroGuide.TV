import AppIntents
import SwiftUI
import WidgetKit

/// The widget in each size, styled like the guide's preview. Each channel
/// change slides in from the side, like the guide flipping channels.
struct WhatsOnView: View {
    let entry: WhatsOnEntry
    @Environment(\.widgetFamily) private var family
    private var colors: WidgetStyle.Colors { entry.colors }

    var body: some View {
        if let channel = entry.channels.first, let program = channel.program(at: entry.date) {
            Group {
                switch family {
                case .systemSmall: small(channel, program)
                case .systemLarge: large(channel, program)
                default: medium(channel, program)
                }
            }
            .widgetURL(WhatsOnStore.url(forChannel: channel.id))
        } else {
            empty
        }
    }

    // MARK: - Sizes

    private func small(_ channel: WhatsOnSnapshot.Channel, _ program: WhatsOnSnapshot.Program) -> some View {
        ZStack(alignment: .bottomLeading) {
            backdrop(program, fade: .bottom)
            VStack(alignment: .leading, spacing: WidgetStyle.Spacing.xs) {
                osd(channel)
                Spacer(minLength: .zero)
                titleLogo(program, maxHeight: WidgetStyle.Size.smallLogoHeight)
                timing(program, compact: true)
            }
            .padding(WidgetStyle.Spacing.lg)
        }
        .slidesBetweenChannels(channel)
    }

    private func medium(_ channel: WhatsOnSnapshot.Channel, _ program: WhatsOnSnapshot.Program) -> some View {
        HStack(spacing: WidgetStyle.Spacing.md) {
            stillPanel(channel, program)
            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: WidgetStyle.Spacing.xs) {
                    titleLogo(program, maxHeight: WidgetStyle.Size.mediumLogoHeight)
                    episode(program)
                    timing(program, compact: false)
                    Spacer(minLength: .zero)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                flipButtons
            }
        }
        .padding(WidgetStyle.Spacing.md)
        .background(alignment: .trailing) {
            backdrop(program, fade: .leading)
        }
        .slidesBetweenChannels(channel)
    }

    private func large(_ channel: WhatsOnSnapshot.Channel, _ program: WhatsOnSnapshot.Program) -> some View {
        VStack(alignment: .leading, spacing: WidgetStyle.Spacing.md) {
            HStack(spacing: WidgetStyle.Spacing.sm) {
                glyph(width: WidgetStyle.Size.glyph)
                wordmark
                Spacer()
                flipButtons
            }
            ZStack(alignment: .bottomLeading) {
                backdrop(program, fade: .bottom)
                VStack(alignment: .leading, spacing: WidgetStyle.Spacing.xs) {
                    osd(channel)
                    Spacer(minLength: .zero)
                    titleLogo(program, maxHeight: WidgetStyle.Size.largeLogoHeight)
                    episode(program)
                    timing(program, compact: false)
                }
                .padding(WidgetStyle.Spacing.md)
            }
            .frame(maxWidth: .infinity)
            .frame(height: WidgetStyle.Size.largeHeroHeight)
            .clipShape(RoundedRectangle(cornerRadius: WidgetStyle.Size.corner))
            .slidesBetweenChannels(channel)
            Text("ON NOW")
                .font(WidgetStyle.Font.section)
                .foregroundStyle(colors.accentSecondary)
            ForEach(entry.channels.dropFirst().prefix(WidgetStyle.Size.otherChannels), id: \.id) { other in
                if let now = other.program(at: entry.date) {
                    otherChannelRow(other, now)
                }
            }
            Spacer(minLength: .zero)
        }
        .padding(WidgetStyle.Spacing.lg)
    }

    private var empty: some View {
        VStack(spacing: WidgetStyle.Spacing.md) {
            glyph(width: WidgetStyle.Size.glyph)
            if family != .systemSmall {
                wordmark
            }
            Text("Tune in to see what's on")
                .font(WidgetStyle.Font.detail)
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(WidgetStyle.Spacing.lg)
    }

    // MARK: - Pieces

    /// The guide's channel number display: green, monospaced, glowing.
    private func osd(_ channel: WhatsOnSnapshot.Channel) -> some View {
        Text("\(channel.number) \(channel.callSign)")
            .font(WidgetStyle.Font.osd)
            .foregroundStyle(colors.osd)
            .shadow(color: colors.osd.opacity(WidgetStyle.Size.glowOpacity), radius: WidgetStyle.Size.glowRadius)
            .lineLimit(1)
    }

    /// Where the guide shows live video: the episode still, dimmed, with the channel.
    private func stillPanel(_ channel: WhatsOnSnapshot.Channel, _ program: WhatsOnSnapshot.Program) -> some View {
        let shape = RoundedRectangle(cornerRadius: WidgetStyle.Size.corner)
        return Color.black
            .overlay {
                if let image = image(program.stillFile ?? program.backdropFile) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .opacity(WidgetStyle.Size.stillOpacity)
                }
            }
            .overlay(alignment: .topLeading) {
                osd(channel)
                    .padding(WidgetStyle.Spacing.sm)
            }
            .aspectRatio(WidgetStyle.Size.stillAspect, contentMode: .fit)
            .clipShape(shape)
    }

    /// The show's title logo, or its name where there's none.
    @ViewBuilder
    private func titleLogo(_ program: WhatsOnSnapshot.Program, maxHeight: CGFloat) -> some View {
        if let logo = image(program.logoFile) {
            Image(uiImage: logo)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: maxHeight, alignment: .leading)
        } else {
            Text(program.title)
                .font(WidgetStyle.Font.title)
                .foregroundStyle(colors.textPrimary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private func episode(_ program: WhatsOnSnapshot.Program) -> some View {
        if let episode = program.episode {
            Text(episode)
                .font(WidgetStyle.Font.episode)
                .foregroundStyle(colors.textPrimary)
                .lineLimit(1)
        }
    }

    /// "8:31 PM – 9:13 PM · 26m left", in the guide's clock style.
    private func timing(_ program: WhatsOnSnapshot.Program, compact: Bool) -> some View {
        let left = WidgetTime.remaining(until: program.end, from: entry.date)
        let text = compact ? left : "\(WidgetTime.range(program.start, program.end)) · \(left)"
        return Text(text)
            .font(compact ? WidgetStyle.Font.clockSmall : WidgetStyle.Font.clock)
            .foregroundStyle(colors.accent)
            .lineLimit(1)
            .minimumScaleFactor(WidgetStyle.Size.minimumScale)
    }

    private func otherChannelRow(_ channel: WhatsOnSnapshot.Channel, _ program: WhatsOnSnapshot.Program) -> some View {
        Link(destination: WhatsOnStore.url(forChannel: channel.id) ?? URL(fileURLWithPath: "/")) {
            HStack(spacing: WidgetStyle.Spacing.sm) {
                osd(channel)
                    .frame(width: WidgetStyle.Size.osdColumn, alignment: .leading)
                Text(program.title)
                    .font(WidgetStyle.Font.detailEmphasis)
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: WidgetStyle.Spacing.xs)
                Text(WidgetTime.remaining(until: program.end, from: entry.date))
                    .font(WidgetStyle.Font.clockSmall)
                    .foregroundStyle(colors.accent)
            }
        }
    }

    private var flipButtons: some View {
        HStack(spacing: WidgetStyle.Spacing.xs) {
            flipButton(step: -1, symbol: "chevron.left")
            flipButton(step: 1, symbol: "chevron.right")
        }
    }

    private func flipButton(step: Int, symbol: String) -> some View {
        Button(intent: FlipChannelIntent(step: step)) {
            Image(systemName: symbol)
                .font(WidgetStyle.Font.button)
                .foregroundStyle(colors.accent)
                .frame(width: WidgetStyle.Size.button, height: WidgetStyle.Size.button)
                .background(colors.surface, in: Circle())
        }
        .buttonStyle(.plain)
    }

    /// The backdrop, filling whatever space it's given without changing its
    /// size, faded toward `fade` so text stays readable (as in the guide).
    private func backdrop(_ program: WhatsOnSnapshot.Program, fade: UnitPoint) -> some View {
        Color.clear
            .overlay {
                if let image = image(program.backdropFile) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .opacity(WidgetStyle.Size.backdropOpacity)
                        .mask(LinearGradient(colors: [.black, .clear], startPoint: fade == .leading ? .trailing : .top, endPoint: fade))
                }
            }
            .clipped()
    }

    private func glyph(width: CGFloat) -> some View {
        TVGlyph()
            .brandFill(colors.accent)
            .frame(width: width)
    }

    private var wordmark: some View {
        (Text("RetroGuide").foregroundStyle(colors.textPrimary)
            + Text(".TV").foregroundStyle(colors.accent))
            .font(WidgetStyle.Font.wordmark)
    }

    private func image(_ file: String?) -> UIImage? {
        WhatsOnStore.artworkURL(file).flatMap { UIImage(contentsOfFile: $0.path) }
    }
}

private extension View {
    /// A new channel slides in from the trailing side.
    func slidesBetweenChannels(_ channel: WhatsOnSnapshot.Channel) -> some View {
        id(channel.id)
            .transition(.push(from: .trailing))
    }
}

/// Times in the guide's words.
enum WidgetTime {
    private static let secondsPerMinute = 60
    private static let minutesPerHour = 60
    private static let noon = 12

    /// "8:46–9:28 PM": the start leaves out AM/PM when it's the same as the end's.
    static func range(_ start: Date, _ end: Date) -> String {
        let full = Date.FormatStyle(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        let samePeriod = (calendar.component(.hour, from: start) < noon) == (calendar.component(.hour, from: end) < noon)
        var startText = start.formatted(full)
        if samePeriod {
            for symbol in [calendar.amSymbol, calendar.pmSymbol] {
                startText = startText.replacingOccurrences(of: symbol, with: "")
            }
            startText = startText.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{202F}")))
        }
        return "\(startText)–\(end.formatted(full))"
    }

    /// "26m left", "1h 5m left".
    static func remaining(until end: Date, from date: Date) -> String {
        let minutes = max(1, Int((end.timeIntervalSince(date) / Double(secondsPerMinute)).rounded(.up)))
        let hours = minutes / minutesPerHour
        return hours > 0 ? "\(hours)h \(minutes % minutesPerHour)m left" : "\(minutes)m left"
    }
}
