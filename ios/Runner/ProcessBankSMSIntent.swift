import AppIntents
import Foundation
import UserNotifications

// MARK: - Shortcuts action

/// "Process Bank SMS" — the action a user adds to a Shortcuts *Message*
/// automation, with its "SMS Text" field set to "Shortcut Input".
///
/// The intent runs inside the app's own process (no UI, the app does not open).
/// It does the minimum: it appends the raw SMS text to a queue file.
/// All parsing and database work stays in Dart (`SmsQueueService`), so Dart
/// remains the only writer of the SQLite database.
struct ProcessBankSMSIntent: AppIntent {
    static let title: LocalizedStringResource = "Process Bank SMS"
    static let description = IntentDescription(
        "Sends a bank SMS to Khazna so it can be logged as a transaction."
    )

    @Parameter(title: "SMS Text")
    var smsText: String

    func perform() async throws -> some IntentResult {
        let status = SMSQueue.append(smsText)
        // Diagnostics only: records THAT the intent ran and how it ended,
        // never the SMS content (only its length).
        SMSQueue.logEvent("perform: textLength=\(smsText.count) result=\(status)")

        // Tell the user the SMS reached Khazna, even with the phone locked and
        // the app closed. Parsing happens when Khazna next opens, so the text
        // says so. Deliberately generic: a lock-screen banner must not reveal
        // amounts or balances.
        if status == "ok" {
            await SMSQueue.postReceivedNotification()
        }
        return .result()
    }
}

// MARK: - Quick "Add Entry" action

/// Which account a quick entry goes to. The raw value is what Dart receives.
enum EntryBank: String, AppEnum {
    case cash, telda, elAhly, mashreq

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static let caseDisplayRepresentations: [EntryBank: DisplayRepresentation] = [
        .cash: "Cash",
        .telda: "Telda",
        .elAhly: "El Ahly",
        .mashreq: "El Mashreq",
    ]

    /// Key understood by `BankIdentifier.bankForKey` on the Dart side.
    var key: String {
        switch self {
        case .cash: return "cash"
        case .telda: return "telda"
        case .elAhly: return "ahly"
        case .mashreq: return "mashreq"
        }
    }
}

enum EntryKind: String, AppEnum {
    case expense, income

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Type"
    static let caseDisplayRepresentations: [EntryKind: DisplayRepresentation] = [
        .expense: "Money out",
        .income: "Money in",
    ]
}

/// "Add Entry" — logs money in or out of one account in one tap, from the lock
/// screen, Back Tap or Shortcuts. Typical uses:
///   * Cash spent            → Account: Cash,  Type: Money out
///   * Telda transfer arrived → Account: Telda, Type: Money in
///
/// Same design as [ProcessBankSMSIntent]: runs in the app process, no UI, only
/// appends one JSON line to the queue. Dart inserts it the next time Khazna
/// opens. The amount is validated here AND in Dart.
struct AddEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Entry"
    static let description = IntentDescription(
        "Logs money in or out of one of your accounts in Khazna."
    )

    @Parameter(title: "Account", default: .cash)
    var bank: EntryBank

    @Parameter(title: "Type", default: .expense)
    var kind: EntryKind

    @Parameter(title: "Amount (EGP)")
    var amount: Double

    @Parameter(title: "Note")
    var note: String?

    func perform() async throws -> some IntentResult {
        let status = SMSQueue.appendEntry(
            bank: bank.key, type: kind.rawValue, amount: amount, note: note)
        SMSQueue.logEvent("addEntry: bank=\(bank.key) type=\(kind.rawValue) result=\(status)")
        if status == "ok" {
            await SMSQueue.postEntryNotification()
        }
        return .result()
    }
}

// MARK: - Queue file

/// Append-only JSON-lines file in Application Support. The Dart side reads the
/// same location through `getApplicationSupportDirectory()` (path_provider).
///
/// One line per entry: {"text": "...", "receivedAt": "<ISO 8601>"} for SMS, or
/// {"kind": "entry", "bank": "cash", "type": "expense", "amount": 50, ...} for Add Entry.
/// JSON encoding keeps multi-line SMS bodies on a single line.
enum SMSQueue {
    static let fileName = "khazna_sms_queue.jsonl"
    private static let lock = NSLock()

    /// Returns a short status string ("ok", "emptyText", ...) for diagnostics.
    @discardableResult
    static func append(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "emptyText" }
        return appendPayload([
            "text": trimmed,
            "receivedAt": ISO8601DateFormatter().string(from: Date()),
        ])
    }

    /// Queues a quick entry:
    /// {"kind":"entry","bank":"telda","type":"income","amount":20,"note":..,"receivedAt":..}
    @discardableResult
    static func appendEntry(bank: String, type: String, amount: Double, note: String?) -> String {
        guard amount.isFinite, amount > 0, amount < 10_000_000 else {
            return "badAmount"
        }
        var payload: [String: Any] = [
            "kind": "entry",
            "bank": bank,
            "type": type,
            "amount": amount,
            "receivedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        let n = (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { payload["note"] = String(n.prefix(120)) }
        return appendPayload(payload)
    }

    /// Serialises [payload] as one JSON line and appends it to the queue file.
    private static func appendPayload(_ payload: [String: Any]) -> String {
        guard let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return "noSupportDir" }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8)
        else { return "jsonEncodeFailed" }
        let lineData = Data((json + "\n").utf8)

        // Several Shortcut runs can overlap; serialize the file access.
        lock.lock()
        defer { lock.unlock() }

        do {
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: lineData)
            } else {
                try lineData.write(to: url, options: .atomic)
            }
            return "ok"
        } catch {
            return "writeFailed: \(error.localizedDescription)"
        }
    }

    // MARK: "SMS received" notification

    static func postReceivedNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "Bank SMS received"
        content.body = "Open Khazna to add it to your transactions."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            logEvent("notification failed: \(error.localizedDescription)")
        }
    }

    static func postEntryNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "Entry saved"
        content.body = "Open Khazna to add it to your transactions."
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            logEvent("entry notification failed: \(error.localizedDescription)")
        }
    }

    // MARK: Diagnostics log

    static let logFileName = "khazna_intent_log.txt"

    /// Appends one timestamped line to a small diagnostics log that the
    /// in-app diagnostics screen displays. Never contains SMS content.
    static func logEvent(_ message: String) {
        guard let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        lock.lock()
        defer { lock.unlock() }
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let url = dir.appendingPathComponent(logFileName)
        do {
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
            } else {
                try Data(line.utf8).write(to: url, options: .atomic)
            }
        } catch {
            // Diagnostics must never break the intent.
        }
    }
}
