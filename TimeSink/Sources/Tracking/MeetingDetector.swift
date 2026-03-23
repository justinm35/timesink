import Foundation

struct MeetingContext: Sendable {
    let isLikelyInMeeting: Bool
    let source: String?
    let confidence: Double

    static let none = MeetingContext(isLikelyInMeeting: false, source: nil, confidence: 0)
}

struct MeetingDetector: Sendable {
    private static let nativeMeetingBundleIds: [String: String] = [
        "us.zoom.xos": "Zoom",
        "com.apple.FaceTime": "FaceTime",
        "com.microsoft.teams": "Teams",
        "com.microsoft.teams2": "Teams",
        "com.tinyspeck.slackmacgap": "Slack",
    ]

    private static let nativeKeywords = [
        "meeting",
        "zoom meeting",
        "facetime",
        "call",
        "huddle",
        "teams",
    ]

    private static let browserMeetingKeywords = [
        "meet.google.com",
        "google meet",
        "zoom.us",
        "zoom meeting",
        "teams.microsoft.com",
        "microsoft teams",
        "slack huddle",
        "slack call",
    ]

    func detect(appName: String, bundleId: String, windowTitle: String, detail: String?) -> MeetingContext {
        let normalizedAppName = appName.lowercased()
        let normalizedTitle = windowTitle.lowercased()
        let normalizedDetail = (detail ?? "").lowercased()

        if let source = Self.nativeMeetingBundleIds[bundleId] {
            if Self.nativeKeywords.contains(where: { normalizedTitle.contains($0) || normalizedDetail.contains($0) }) {
                return MeetingContext(isLikelyInMeeting: true, source: source, confidence: 0.95)
            }
            return MeetingContext(isLikelyInMeeting: true, source: source, confidence: 0.82)
        }

        if ["zoom", "facetime", "teams", "slack"].contains(where: { normalizedAppName.contains($0) }) {
            if Self.nativeKeywords.contains(where: { normalizedTitle.contains($0) || normalizedDetail.contains($0) }) {
                return MeetingContext(isLikelyInMeeting: true, source: appName, confidence: 0.9)
            }
        }

        if Self.browserMeetingKeywords.contains(where: { normalizedDetail.contains($0) }) {
            return MeetingContext(isLikelyInMeeting: true, source: appName, confidence: 0.9)
        }

        if Self.browserMeetingKeywords.contains(where: { normalizedTitle.contains($0) }) {
            return MeetingContext(isLikelyInMeeting: true, source: appName, confidence: 0.78)
        }

        return .none
    }
}
