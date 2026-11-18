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
        SMSQueue.append(smsText)
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

    static func append(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let dir = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }

        let payload: [String: String] = [
            "text": trimmed,
            "receivedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8)
        else { return }
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
        } catch {
            // Nothing sensible to do inside a background intent; drop the line.
        }
    }
}
