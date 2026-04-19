import Foundation

// Ollami: analytics removed — all methods are no-ops
@MainActor
class AnalyticsManager {
  static let shared = AnalyticsManager()
  nonisolated static var isDevBuild: Bool { true }
  private init() {}

  func initialize() {}
  func identify() {}
  func reset() {}
  func optInTracking() {}
  func optOutTracking() {}

  // MARK: - Onboarding
  func onboardingStepCompleted(step: Int, stepName: String) {}
  func onboardingHowDidYouHear(source: String) {}
  func onboardingCompleted() {}
  func onboardingChatToolUsed(tool: String, properties: [String: Any] = [:]) {}
  func onboardingChatMessage(role: String, step: String) {}
  func onboardingChatMessageDetailed(role: String, text: String, step: String, toolCalls: [String]? = nil, model: String? = nil, error: String? = nil) {}

  // MARK: - Auth
  func signInStarted(provider: String) {}
  func signInCompleted(provider: String) {}
  func signInFailed(provider: String, error: String) {}
  func signedOut() {}

  // MARK: - Monitoring / Transcription
  func monitoringStarted() {}
  func monitoringStopped() {}
  func distractionDetected(app: String, windowTitle: String?) {}
  func focusRestored(app: String) {}
  func transcriptionStarted() {}
  func transcriptionStopped(wordCount: Int) {}
  func recordingError(error: String) {}

  // MARK: - Permissions
  func permissionRequested(permission: String, extraProperties: [String: Any] = [:]) {}
  func permissionGranted(permission: String, extraProperties: [String: Any] = [:]) {}
  func permissionDenied(permission: String, extraProperties: [String: Any] = [:]) {}
  func permissionSkipped(permission: String, extraProperties: [String: Any] = [:]) {}

  // MARK: - Bluetooth / Screen Capture / Notifications
  func bluetoothStateChanged(oldState: String, newState: String, oldStateRaw: Int, newStateRaw: Int, authorization: String, authorizationRaw: Int) {}
  func screenCaptureBrokenDetected() {}
  func screenCaptureResetClicked(source: String) {}
  func screenCaptureResetCompleted(success: Bool) {}
  func notificationRepairTriggered(reason: String, previousStatus: String, currentStatus: String) {}
  func notificationSettingsChecked(authStatus: String, alertStyle: String, soundEnabled: Bool, badgeEnabled: Bool, bannersDisabled: Bool) {}

  // MARK: - App Lifecycle
  func detectAndReportCrash() {}
  func appLaunched() {}
  func trackStartupTiming(dbInitMs: Double, timeToInteractiveMs: Double, hadUncleanShutdown: Bool, databaseInitFailed: Bool) {}
  func trackFirstLaunchIfNeeded() {}
  func appBecameActive() {}
  func appResignedActive() {}

  // MARK: - Conversations / Memories
  func conversationCreated(conversationId: String, source: String, durationSeconds: Int? = nil) {}
  func memoryDeleted(conversationId: String) {}
  func memoryShareButtonClicked(conversationId: String) {}
  func shareAction(category: String, properties: [String: Any] = [:]) {}
  func memoryListItemClicked(conversationId: String) {}
  func memoryExtracted(memoryCount: Int) {}

  // MARK: - Chat
  func chatMessageSent(messageLength: Int, hasContext: Bool = false, source: String) {}
  func chatAppSelected(appId: String?, appName: String?) {}
  func chatCleared() {}
  func chatSessionCreated() {}
  func chatSessionDeleted() {}
  func messageRated(rating: Int) {}
  func initialMessageGenerated(hasApp: Bool) {}
  func sessionTitleGenerated() {}
  func chatStarredFilterToggled(enabled: Bool) {}
  func sessionRenamed() {}
  func chatAgentQueryCompleted(durationMs: Int, toolCallCount: Int, toolNames: [String], costUsd: Double, messageLength: Int) {}
  func chatToolCallCompleted(toolName: String, durationMs: Int) {}
  func chatAgentError(error: String, rawError: String? = nil) {}
  func chatBridgeModeChanged(from oldMode: String, to newMode: String) {}

  // MARK: - Navigation / Settings
  func searchQueryEntered(query: String) {}
  func searchBarFocused() {}
  func settingsPageOpened() {}
  func pageViewed(_ pageName: String) {}
  func tabChanged(tabName: String) {}
  func conversationDetailOpened(conversationId: String) {}
  func conversationReprocessed(conversationId: String, appId: String) {}
  func settingToggled(setting: String, enabled: Bool) {}
  func languageChanged(language: String) {}
  func launchAtLoginStatusChecked(enabled: Bool) {}
  func launchAtLoginChanged(enabled: Bool, source: String) {}
  func trackSettingsState(screenshotsEnabled: Bool, memoryExtractionEnabled: Bool, memoryNotificationsEnabled: Bool) {}
  func reportAllSettingsIfNeeded() {}

  // MARK: - Account
  func deleteAccountClicked() {}
  func deleteAccountConfirmed() {}
  func deleteAccountCancelled() {}

  // MARK: - Feedback
  func feedbackOpened() {}
  func feedbackSubmitted(feedbackLength: Int) {}

  // MARK: - Rewind
  func rewindSearchPerformed(queryLength: Int) {}
  func rewindScreenshotViewed(timestamp: Date) {}
  func rewindTimelineNavigated(direction: String) {}

  // MARK: - Focus / Tasks
  func focusAlertShown(app: String) {}
  func focusAlertDismissed(app: String, action: String) {}
  func taskExtracted(taskCount: Int) {}
  func taskPromoted(taskCount: Int) {}
  func taskCompleted(source: String?) {}
  func taskDeleted(source: String?) {}
  func taskAdded() {}

  // MARK: - Insights / Apps
  func insightGenerated(category: String?) {}
  func appEnabled(appId: String, appName: String) {}
  func appDisabled(appId: String, appName: String) {}
  func appDetailViewed(appId: String, appName: String) {}

  // MARK: - Updates
  func updateCheckStarted() {}
  func updateAvailable(version: String) {}
  func updateInstalled(version: String) {}
  func updateNotFound() {}
  func updateCheckFailed(error: String, errorDomain: String, errorCode: Int, underlyingError: String? = nil, underlyingDomain: String? = nil, underlyingCode: Int? = nil) {}

  // MARK: - Notification Events
  func notificationSent(notificationId: String, title: String, assistantId: String, surface: String) {}
  func notificationClicked(notificationId: String, title: String, assistantId: String, surface: String) {}
  func notificationDismissed(notificationId: String, title: String, assistantId: String, surface: String) {}
  func notificationWillPresent(notificationId: String, title: String) {}
  func notificationDelegateReady() {}

  // MARK: - Menu Bar
  func menuBarOpened() {}
  func menuBarActionClicked(action: String) {}

  // MARK: - Tier
  func tierChanged(tier: Int, reason: String) {}

  // MARK: - Floating Bar
  func floatingBarToggled(visible: Bool, source: String) {}
  func floatingBarAskOmiOpened(source: String) {}
  func floatingBarAskOmiClosed() {}
  func floatingBarQuerySent(messageLength: Int, hasScreenshot: Bool) {}
  func floatingBarPTTStarted(mode: String) {}
  func floatingBarPTTEnded(mode: String, hadTranscript: Bool, transcriptLength: Int) {}

  // MARK: - Knowledge Graph
  func knowledgeGraphBuildStarted(filesIndexed: Int, hadExistingGraph: Bool) {}
  func knowledgeGraphBuildCompleted(nodeCount: Int, edgeCount: Int, pollAttempts: Int, hadExistingGraph: Bool) {}
  func knowledgeGraphBuildFailed(reason: String, pollAttempts: Int, filesIndexed: Int) {}

  // MARK: - Display
  func trackDisplayInfo() {}
}
