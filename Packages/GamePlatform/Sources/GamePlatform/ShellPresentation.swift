import Foundation

/// Title-authored presentation copy for the shared flow. It contains no game rules.
public struct ShellPresentation: Sendable {
    public let openingMessage: String
    public let menuHeading: String
    public let menuMessage: String
    public let startLabel: String
    public let loadingMessage: String
    public let pauseMessage: String
    public let audioPauseMessage: String
    public let restartLabel: String
    public let successHeading: String
    public let successMessage: String
    public let failureHeading: String
    public let failureMessage: String
    public let retryLabel: String
    /// The success page's continue action; the failure page keeps `retryLabel`.
    public let successRetryLabel: String
    public let languageName: String
    public let languageMessage: String

    public init(openingMessage: String, menuHeading: String, menuMessage: String,
                startLabel: String, loadingMessage: String, pauseMessage: String,
                audioPauseMessage: String, restartLabel: String, successHeading: String,
                successMessage: String, failureHeading: String, failureMessage: String,
                retryLabel: String, successRetryLabel: String? = nil,
                languageName: String, languageMessage: String) {
        self.openingMessage = openingMessage
        self.menuHeading = menuHeading
        self.menuMessage = menuMessage
        self.startLabel = startLabel
        self.loadingMessage = loadingMessage
        self.pauseMessage = pauseMessage
        self.audioPauseMessage = audioPauseMessage
        self.restartLabel = restartLabel
        self.successHeading = successHeading
        self.successMessage = successMessage
        self.failureHeading = failureHeading
        self.failureMessage = failureMessage
        self.retryLabel = retryLabel
        self.successRetryLabel = successRetryLabel ?? retryLabel
        self.languageName = languageName
        self.languageMessage = languageMessage
    }
}
