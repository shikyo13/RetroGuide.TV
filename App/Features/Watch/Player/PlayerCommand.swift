/// What the viewer can do while watching full screen. The Siri Remote and the
/// touch controls both translate their input into these commands.
enum PlayerCommand {
    case channelUp
    case channelDown
    /// Show what's on now, or step forward to what's next when already showing.
    case showInfo
    /// Show what's on now.
    case showNow
    /// Show what's on next.
    case showNext
    /// Hide the info banner (touch only; on Apple TV it times out).
    case hideInfo
    case openGuide
    case lastChannel
}
