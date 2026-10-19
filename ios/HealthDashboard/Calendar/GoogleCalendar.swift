import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// The iOS OAuth client ID from Google Cloud (Credentials → OAuth client ID → iOS).
/// It isn't a secret. Empty until set up; the app then offers Apple Calendar and the link instead.
enum GoogleConfig {
    static let clientID = "272901953650-i04kc39l8ee061e6c00320qokomstb7i.apps.googleusercontent.com"
}

enum GoogleError: LocalizedError {
    case notConfigured, cancelled, signedOut, failed(String)
    var errorDescription: String? {
        switch self {
        case .notConfigured: "Google sign-in isn’t set up yet."
        case .cancelled: "Sign-in was cancelled."
        case .signedOut: "Google signed you out. Sign in again to keep reading your calendar."
        case .failed(let message): message
        }
    }
}

/// "Sign in with Google" without Google's SDK: Google's own sign-in page in a secure browser
/// sheet (OAuth with PKCE), read-only calendar access, and the refresh token kept in the Keychain.
@MainActor
final class GoogleAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleAuth()

    static let scope = "https://www.googleapis.com/auth/calendar.readonly"
    private static let refreshAccount = "googleRefreshToken"

    private var accessToken: String?
    private var expiry = Date.distantPast
    private var session: ASWebAuthenticationSession?

    var isConfigured: Bool { !GoogleConfig.clientID.isEmpty }
    var isSignedIn: Bool { Keychain.get(Self.refreshAccount) != nil }

    /// Google's iOS clients call back to the reversed client ID.
    private var scheme: String {
        "com.googleusercontent.apps." + GoogleConfig.clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }
    private var redirectURI: String { scheme + ":/oauth2redirect" }

    func signIn() async throws {
        guard isConfigured else { throw GoogleError.notConfigured }
        let verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = Self.randomString(24)
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            .init(name: "client_id", value: GoogleConfig.clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]
        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: c.url!, callbackURLScheme: scheme) { url, error in
                if let url { cont.resume(returning: url) }
                else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { cont.resume(throwing: GoogleError.cancelled) }
                else { cont.resume(throwing: GoogleError.failed(error?.localizedDescription ?? "Sign-in didn’t finish.")) }
            }
            s.presentationContextProvider = self
            session = s
            s.start()
        }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { throw GoogleError.failed("Sign-in didn’t match. Try again.") }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw GoogleError.failed(items.first(where: { $0.name == "error" })?.value == "access_denied" ? "Calendar access wasn’t allowed." : "Google didn’t send a sign-in code.")
        }
        let json = try await tokenRequest([
            "code": code, "client_id": GoogleConfig.clientID, "redirect_uri": redirectURI,
            "grant_type": "authorization_code", "code_verifier": verifier,
        ])
        guard let refresh = json["refresh_token"] as? String else { throw GoogleError.failed("Google didn’t grant lasting access. Try again.") }
        Keychain.set(refresh, for: Self.refreshAccount)
        store(json)
    }

    /// A valid access token, refreshing it from the Keychain token when needed.
    func token() async throws -> String {
        if let accessToken, expiry > .now.addingTimeInterval(60) { return accessToken }
        guard let refresh = Keychain.get(Self.refreshAccount) else { throw GoogleError.signedOut }
        do {
            let json = try await tokenRequest(["refresh_token": refresh, "client_id": GoogleConfig.clientID, "grant_type": "refresh_token"])
            store(json)
            return accessToken!
        } catch GoogleError.failed(let message) where message == "invalid_grant" {
            signOut()
            throw GoogleError.signedOut
        }
    }

    func signOut() {
        if let refresh = Keychain.get(Self.refreshAccount) {
            var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke?token=\(refresh)")!)
            r.httpMethod = "POST"
            URLSession.shared.dataTask(with: r).resume()
        }
        Keychain.set(nil, for: Self.refreshAccount)
        accessToken = nil
        expiry = .distantPast
    }

    private func store(_ json: [String: Any]) {
        accessToken = json["access_token"] as? String
        expiry = .now.addingTimeInterval((json["expires_in"] as? Double) ?? 3000)
    }

    private func tokenRequest(_ form: [String: String]) async throws -> [String: Any] {
        var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        r.httpBody = body.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: r)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw GoogleError.failed(json["error"] as? String ?? "Google sign-in failed.")
        }
        return json
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }

    private static func randomString(_ length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<length).map { _ in chars.randomElement()! })
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

/// Reads events from every calendar shown in her Google Calendar, from a year back to two months ahead.
enum GoogleCalendarAPI {
    static func events() async throws -> [CalendarEvent] {
        let token = try await GoogleAuth.shared.token()
        let list = try await get("https://www.googleapis.com/calendar/v3/users/me/calendarList?minAccessRole=reader", token)
        let calendars = (list["items"] as? [[String: Any]] ?? []).filter { ($0["selected"] as? Bool) == true || ($0["primary"] as? Bool) == true }
        let iso = ISO8601DateFormatter()
        let timeMin = iso.string(from: Calendar.current.date(byAdding: .day, value: -365, to: .now)!)
        let timeMax = iso.string(from: Calendar.current.date(byAdding: .day, value: 60, to: .now)!)
        var all: [CalendarEvent] = []
        for cal in calendars {
            guard let id = (cal["id"] as? String)?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/@#"))) else { continue }
            var pageToken: String?
            repeat {
                var url = "https://www.googleapis.com/calendar/v3/calendars/\(id)/events?singleEvents=true&maxResults=2500&timeMin=\(timeMin)&timeMax=\(timeMax)"
                    .replacingOccurrences(of: "+", with: "%2B")
                if let pageToken { url += "&pageToken=\(pageToken)" }
                let page = try await get(url, token)
                all += googleEvents(page)
                pageToken = page["nextPageToken"] as? String
            } while pageToken != nil
        }
        return all.sorted { ($0.date, $0.minutes ?? -1) < ($1.date, $1.minutes ?? -1) }
    }

    private static func get(_ url: String, _ token: String) async throws -> [String: Any] {
        var r = URLRequest(url: URL(string: url)!)
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: r)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw GoogleError.signedOut }
        guard code == 200, let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw GoogleError.failed("Couldn’t read Google Calendar (error \(code)).")
        }
        return json
    }
}

/// Turns one page of Google Calendar events into the app's events. Like the link reader, it skips
/// repeating events (classes, office hours) and cancelled ones, since exams are one-offs.
func googleEvents(_ page: [String: Any], timeZone: TimeZone = .current) -> [CalendarEvent] {
    let iso = ISO8601DateFormatter()
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = timeZone
    return (page["items"] as? [[String: Any]] ?? []).compactMap { item in
        guard item["status"] as? String != "cancelled", item["recurringEventId"] == nil,
              let title = item["summary"] as? String, let start = item["start"] as? [String: Any] else { return nil }
        if let day = start["date"] as? String { return CalendarEvent(title: title, date: day, minutes: nil) }
        guard let text = start["dateTime"] as? String, let date = iso.date(from: text) else { return nil }
        let parts = cal.dateComponents([.hour, .minute], from: date)
        return CalendarEvent(title: title, date: Day.key(date, in: timeZone), minutes: parts.hour! * 60 + parts.minute!)
    }
}
