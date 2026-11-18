import AppIntents
import Foundation

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
        return .result()
    }
}

// MARK: - Queue file

/// Append-only JSON-lines file in Application Support. The Dart side reads the
/// same location through `getApplicationSupportDirectory()` (path_provider).
///
/// One line per message: {"text": "...", "receivedAt": "<ISO 8601>"}.
/// JSON encoding keeps multi-line SMS bodies on a single line.
enum SMSQueue {
    static let fileName = "khazna_sms_queue.jsonl"
    private static let lock = NSLock()

    /// Returns a short status string ("ok", "emptyText", ...) for diagnostics.
    @discardableResult
    static func append(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "emptyText" }
        guard let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return "noSupportDir" }

        let payload: [String: String] = [
            "text": trimmed,
            "receivedAt": ISO8601DateFormatter().string(from: Date()),
        ]
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
