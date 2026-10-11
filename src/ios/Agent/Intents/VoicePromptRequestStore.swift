import Combine
import Foundation

/// One press of the Voice Prompt shortcut: "start listening in this chat".
struct VoicePromptRequest: Equatable {
    /// The session to listen in, or nil for the chat that is open.
    var session: String?
    /// Two presses are two requests, even for the same chat.
    let token = UUID()
}

/// Carries one "start voice input" request from `VoicePromptIntent` (the
/// Action Button, Back Tap, a Shortcut) to the chat that should listen, and
/// starts the listening there.
///
/// The intent runs before the window exists on a cold start and SwiftUI owns
/// the voice panel, so it leaves a request here and the chat consumes it once
/// it is on screen — the pattern `NotificationNavigationStore` uses for
/// notification taps. A request names a session, or nothing; a request for
/// nothing is for the chat that is open (the first mounted chat takes it).
@MainActor
final class VoicePromptRequestStore: ObservableObject {
    static let shared = VoicePromptRequestStore()

    /// Non-nil while a request waits for its chat.
    @Published private(set) var pending: VoicePromptRequest?
    private var requestedAt: Date?

    /// A request older than this is dropped unanswered: the app took too long
    /// to come up, or the chat it named never did. Long enough for a cold
    /// start on an old phone.
    static let staleAfter: TimeInterval = 30

    private init() {}

    /// Called from `VoicePromptIntent.perform()`.
    func request(session: String?) {
        requestedAt = Date()
        pending = VoicePromptRequest(session: session)
    }

    /// The chat `sessionId` takes the request meant for it, once; a request
    /// that names no session is for any chat that is open.
    func take(for sessionId: String?) -> Bool {
        guard let request = pending else { return false }
        if let at = requestedAt, Date().timeIntervalSince(at) > Self.staleAfter {
            pending = nil
            return false
        }
        guard request.session == nil || request.session == sessionId else { return false }
        pending = nil
        return true
    }

    /// Listening in the chat that took a request: into voice mode the way the
    /// mic button goes (`enterVoice` is the chat's switch), then the panel's
    /// own mic once the panel is up. `InlineVoiceInputView.onAppear` prepares
    /// the model (the provider, the permission state) on the render that shows
    /// it, so the press waits for that render; a panel that is already
    /// listening is left alone.
    static func listen(with voice: VoiceInputViewModel, enterVoice: () -> Void) {
        let mode = VoiceModePreference.shared
        if !mode.isVoiceActive { enterVoice() }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard mode.isVoiceActive, !mode.isCapturing else { return }
            voice.handleMainButtonTap()
        }
    }
}
