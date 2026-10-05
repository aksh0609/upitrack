import AppIntents
import Foundation

/// A Shortcuts action, "Log Bank SMS", that hands a bank SMS to UPI Track.
///
/// iOS doesn't let apps read SMS, but a Shortcuts *Message* automation can
/// run this action whenever a bank SMS arrives. The message is saved as a
/// small JSON file in the app's own Documents folder; the Flutter side
/// (lib/data/shortcut_inbox.dart) picks it up, parses it and deletes it the
/// next time the app opens. Nothing leaves the phone.
@available(iOS 16.0, *)
struct LogBankSmsIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Bank SMS"
    // openAppWhenRun defaults to false, so the automation runs silently.

    @Parameter(title: "Message")
    var message: String

    @Parameter(title: "Sender")
    var sender: String?

    func perform() async throws -> some IntentResult {
        try BankSmsInbox.save(body: message, sender: sender ?? "")
        return .result()
    }
}

enum BankSmsInbox {
    /// Must match the folder name in lib/data/shortcut_inbox.dart.
    static let folderName = ".sms_inbox"

    static func save(body: String, sender: String) throws {
        let documents = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let folder = documents.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true)

        let payload: [String: Any] = [
            "body": body,
            "sender": sender,
            "date": Int64(Date().timeIntervalSince1970 * 1000),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let file = folder.appendingPathComponent("\(UUID().uuidString).json")
        try data.write(to: file, options: .atomic)
    }
}
