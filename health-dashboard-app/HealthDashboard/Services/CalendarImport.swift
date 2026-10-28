import AuthenticationServices
import CryptoKit
import EventKit
import Foundation
import HealthCore
import Security
import UIKit

/// One event read from a calendar.
struct CalendarEvent: Equatable {
    /// The calendar's own id, so a re-import updates the exam instead of adding it twice.
    var id: String
    var title: String
    /// The day it's on (midnight).
    var day: Date
    /// Start, minutes after midnight; nil for all-day events.
    var start: Minutes?
}

/// Where exams are read from. Read-only: the app never changes a calendar.
enum CalendarSource: String {
    case apple, google

    var name: String { self == .apple ? "Apple Calendar" : "Google Calendar" }
}

enum CalendarImportError: LocalizedError {
    case denied, notConfigured, cancelled, signedOut, failed(String)
    var errorDescription: String? {
        switch self {
        case .denied: "Calendar access is off for Health Next. Turn it on in Settings \u{2192} Health Next \u{2192} Calendars."
        case .notConfigured: "Google sign-in isn\u{2019}t set up in this build."
        case .cancelled: "Sign-in was cancelled."
        case .signedOut: "Google signed you out. Connect again to keep finding exams."
        case let .failed(message): message
        }
    }
}

/// Finds exams on her Apple or Google calendar (events with exam, midterm,
/// final, quiz or test in the title, from today to four months ahead) and
/// keeps them in the exam list. Exams she added herself are never touched.
@MainActor
final class CalendarImport: ObservableObject {
    static let shared = CalendarImport()

    @Published private(set) var source: CalendarSource? = UserDefaults.standard.string(forKey: CalendarImport.sourceKey).flatMap(CalendarSource.init)
    @Published private(set) var lastChecked: Date? = UserDefaults.standard.object(forKey: CalendarImport.checkedKey) as? Date
    @Published private(set) var working = false
    @Published var error: String?

    private static let sourceKey = "calendarSource"
    private static let checkedKey = "calendarLastChecked"
    private let eventStore = EKEventStore()

    // MARK: Connecting

    func connect(_ new: CalendarSource, model: AppModel) async {
        error = nil
        do {
            switch new {
            case .apple:
                let granted = try await eventStore.requestFullAccessToEvents()
                guard granted else { throw CalendarImportError.denied }
            case .google:
                try await GoogleAuth.shared.signIn()
            }
            setSource(new)
            await check(model: model, force: true)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Stops reading the calendar. Exams already imported stay in the list.
    func disconnect() {
        if source == .google { GoogleAuth.shared.signOut() }
        setSource(nil)
        error = nil
    }

    private func setSource(_ s: CalendarSource?) {
        source = s
        UserDefaults.standard.set(s?.rawValue, forKey: Self.sourceKey)
    }

    // MARK: Reading

    /// Reads the calendar and updates the exam list. Called when the app comes
    /// forward (at most every 30 minutes) and from "Check now".
    func check(model: AppModel, force: Bool = false) async {
        guard let source, !working, !DemoMode.isOn else { return }
        if !force, let lastChecked, Date().timeIntervalSince(lastChecked) < 30 * 60 { return }
        working = true
        defer { working = false }
        do {
            let events = source == .apple ? try appleEvents() : try await GoogleCalendarAPI.events()
            model.mergeCalendarExams(events, source: source.rawValue)
            lastChecked = .now
            UserDefaults.standard.set(lastChecked, forKey: Self.checkedKey)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func appleEvents() throws -> [CalendarEvent] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw CalendarImportError.denied }
        let cal = Calendar.current
        let from = cal.startOfDay(for: .now)
        guard let to = cal.date(byAdding: .month, value: 4, to: from) else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: from, end: to, calendars: nil)
        // Repeating events are classes and office hours; exams are one-offs.
        return eventStore.events(matching: predicate)
            .filter { !$0.hasRecurrenceRules && $0.status != .canceled }
            .map { e in
                let parts = cal.dateComponents([.hour, .minute], from: e.startDate)
                return CalendarEvent(id: e.calendarItemIdentifier, title: e.title ?? "", day: cal.startOfDay(for: e.startDate),
                                     start: e.isAllDay ? nil : (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            }
    }
}

extension AppModel {
    /// Adds and updates the exams found on her calendar, and removes upcoming
    /// ones that came from it and are no longer there (moved or cancelled).
    /// Exams she added or edited herself (no `source`) are never touched.
    func mergeCalendarExams(_ events: [CalendarEvent], source: String) {
        let cal = Calendar.current
        let today = AppDay.day()
        let found = events.filter { ExamDetector.isExam($0.title) && $0.day >= today }
        let keys = Set(found.map { "\(source):\($0.id)" })
        var exams = store.data.exams
        let editedHere = Set(exams.compactMap { e in e.source.flatMap { $0.hasPrefix("edited:") ? String($0.dropFirst(7)) : nil } })
        exams.removeAll { e in
            guard let s = e.source, s.hasPrefix(source + ":") else { return false }
            return cal.startOfDay(for: e.date) >= today && !keys.contains(s)
        }
        for event in found {
            let key = "\(source):\(event.id)"
            if editedHere.contains(key) { continue }
            // All-day exams get a 9:00am start; she can change it.
            let start = event.start ?? 540
            if let i = exams.firstIndex(where: { $0.source == key }) {
                exams[i].title = event.title
                exams[i].kind = ExamDetector.kind(of: event.title)
                exams[i].date = event.day
                exams[i].start = start
            } else {
                exams.append(AppData.Exam(title: event.title, kind: ExamDetector.kind(of: event.title),
                                          date: event.day, start: start, source: key))
            }
        }
        if exams != store.data.exams { store.data.exams = exams }
    }
}

// MARK: - Google

/// The iOS OAuth client from Google Cloud (Credentials → OAuth client ID →
/// iOS). Not a secret. It was made for the older app's bundle id
/// (com.ashleylibasci.healthdashboard); if Google refuses sign-in for Health
/// Next, add an iOS client for com.ashleylibasci.healthdashboard.next and
/// put its id here.
enum GoogleConfig {
    static let clientID = "272901953650-i04kc39l8ee061e6c00320qokomstb7i.apps.googleusercontent.com"
}

/// "Sign in with Google" without Google's SDK: Google's own sign-in page in
/// a secure browser sheet (OAuth with PKCE), read-only calendar access, and
/// the refresh token kept in the Keychain.
@MainActor
final class GoogleAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleAuth()

    static let scope = "https://www.googleapis.com/auth/calendar.readonly"
    private static let refreshAccount = "googleRefreshToken"

    private var accessToken: String?
    private var expiry = Date.distantPast
    private var session: ASWebAuthenticationSession?

    var isConfigured: Bool { !GoogleConfig.clientID.isEmpty }

    /// Google's iOS clients call back to the reversed client id.
    private var scheme: String {
        "com.googleusercontent.apps." + GoogleConfig.clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }
    private var redirectURI: String { scheme + ":/oauth2redirect" }

    func signIn() async throws {
        guard isConfigured else { throw CalendarImportError.notConfigured }
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
                else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { cont.resume(throwing: CalendarImportError.cancelled) }
                else { cont.resume(throwing: CalendarImportError.failed(error?.localizedDescription ?? "Sign-in didn\u{2019}t finish.")) }
            }
            s.presentationContextProvider = self
            session = s
            s.start()
        }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else {
            throw CalendarImportError.failed("Sign-in didn\u{2019}t match. Try again.")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw CalendarImportError.failed(items.first(where: { $0.name == "error" })?.value == "access_denied"
                ? "Calendar access wasn\u{2019}t allowed." : "Google didn\u{2019}t send a sign-in code.")
        }
        let json = try await tokenRequest([
            "code": code, "client_id": GoogleConfig.clientID, "redirect_uri": redirectURI,
            "grant_type": "authorization_code", "code_verifier": verifier,
        ])
        guard let refresh = json["refresh_token"] as? String else {
            throw CalendarImportError.failed("Google didn\u{2019}t grant lasting access. Try again.")
        }
        Keychain.set(refresh, for: Self.refreshAccount)
        store(json)
    }

    /// A valid access token, refreshed from the Keychain token when needed.
    func token() async throws -> String {
        if let accessToken, expiry > .now.addingTimeInterval(60) { return accessToken }
        guard let refresh = Keychain.get(Self.refreshAccount) else { throw CalendarImportError.signedOut }
        do {
            let json = try await tokenRequest(["refresh_token": refresh, "client_id": GoogleConfig.clientID, "grant_type": "refresh_token"])
            store(json)
            guard let accessToken else { throw CalendarImportError.signedOut }
            return accessToken
        } catch CalendarImportError.failed(let message) where message == "invalid_grant" {
            signOut()
            throw CalendarImportError.signedOut
        }
    }

    func signOut() {
        if let refresh = Keychain.get(Self.refreshAccount),
           let url = URL(string: "https://oauth2.googleapis.com/revoke?token=\(refresh)") {
            var r = URLRequest(url: url)
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
            throw CalendarImportError.failed(json["error"] as? String ?? "Google sign-in failed.")
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

/// Reads one-off events from every calendar shown in her Google Calendar,
/// from today to four months ahead.
enum GoogleCalendarAPI {
    static func events() async throws -> [CalendarEvent] {
        let token = try await GoogleAuth.shared.token()
        let list = try await get("https://www.googleapis.com/calendar/v3/users/me/calendarList?minAccessRole=reader", token)
        let calendars = (list["items"] as? [[String: Any]] ?? []).filter { ($0["selected"] as? Bool) == true || ($0["primary"] as? Bool) == true }
        let iso = ISO8601DateFormatter()
        let cal = Calendar.current
        let from = cal.startOfDay(for: .now)
        let timeMin = iso.string(from: from)
        let timeMax = iso.string(from: cal.date(byAdding: .month, value: 4, to: from) ?? from)
        var all: [CalendarEvent] = []
        for c in calendars {
            guard let id = (c["id"] as? String)?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/@#"))) else { continue }
            var pageToken: String?
            repeat {
                var url = "https://www.googleapis.com/calendar/v3/calendars/\(id)/events?singleEvents=true&maxResults=2500&timeMin=\(timeMin)&timeMax=\(timeMax)"
                    .replacingOccurrences(of: "+", with: "%2B")
                if let pageToken { url += "&pageToken=\(pageToken)" }
                let page = try await get(url, token)
                all += parse(page)
                pageToken = page["nextPageToken"] as? String
            } while pageToken != nil
        }
        return all
    }

    /// Skips repeating events (classes, office hours) and cancelled ones.
    static func parse(_ page: [String: Any], calendar: Calendar = .current) -> [CalendarEvent] {
        let iso = ISO8601DateFormatter()
        let dayFormat = DateFormatter()
        dayFormat.calendar = calendar
        dayFormat.timeZone = calendar.timeZone
        dayFormat.dateFormat = "yyyy-MM-dd"
        return (page["items"] as? [[String: Any]] ?? []).compactMap { item in
            guard item["status"] as? String != "cancelled", item["recurringEventId"] == nil,
                  let id = item["id"] as? String, let title = item["summary"] as? String,
                  let start = item["start"] as? [String: Any] else { return nil }
            if let dayText = start["date"] as? String, let day = dayFormat.date(from: dayText) {
                return CalendarEvent(id: id, title: title, day: calendar.startOfDay(for: day), start: nil)
            }
            guard let text = start["dateTime"] as? String, let date = iso.date(from: text) else { return nil }
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return CalendarEvent(id: id, title: title, day: calendar.startOfDay(for: date),
                                 start: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        }
    }

    private static func get(_ url: String, _ token: String) async throws -> [String: Any] {
        guard let u = URL(string: url) else { throw CalendarImportError.failed("Couldn\u{2019}t read Google Calendar.") }
        var r = URLRequest(url: u)
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: r)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw CalendarImportError.signedOut }
        guard code == 200, let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw CalendarImportError.failed("Couldn\u{2019}t read Google Calendar (error \(code)).")
        }
        return json
    }
}

/// The Google refresh token, in the phone's Keychain rather than in settings.
enum Keychain {
    private static let service = "com.ashleylibasci.healthdashboard.next"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
