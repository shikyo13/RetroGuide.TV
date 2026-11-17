import RetroGuideKit

extension AppModel {
    /// "12 · Laugh Track" from the current lineup, so the channel shows in this
    /// device's language. A reminder saved its channel's name in the language of
    /// the device that set it; that text is used only when the channel is gone.
    func channelLabel(for reminder: ProgramReminder) -> String {
        guard let channel = visibleChannels.first(where: { $0.isIdentified(by: reminder.channelID) }) else {
            return reminder.channelName
        }
        return "\(channel.number) · \(channel.name)"
    }
}
