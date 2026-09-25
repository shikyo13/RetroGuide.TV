import RetroTVKit
import SwiftUI

/// Full-screen states layered over the video: tuning static, intermission and no signal.
struct SignalOverlay: View {
    let signal: Tuner.Signal
    let channel: Channel?
    let program: ScheduledProgram?

    var body: some View {
        ZStack {
            switch signal {
            case .tuning:
                StaticNoiseView()
                    .transition(.opacity)
            case .intermission:
                if let channel, let program {
                    IntermissionCard(channel: channel, program: program)
                        .transition(.opacity)
                }
            case let .noSignal(message):
                NoSignalCard(message: message)
                    .transition(.opacity)
            case .off, .live:
                EmptyView()
            }
        }
        .animation(DesignTokens.Motion.standardEase, value: signal)
        .allowsHitTesting(false)
    }
}
