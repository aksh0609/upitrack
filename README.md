# UPI Track

A money tracker for India that records payments from **every UPI app** (PhonePe, Google Pay, Paytm, BHIM, CRED, bank apps) without connecting to any of them.

Every UPI payment makes your bank send an SMS. UPI Track turns those bank SMS into a clean list of transactions and shows where your money went each month. Bank and UPI app statements can be imported to fill in history. Everything is processed on the phone: no server, no login.

| | Android | iPhone |
| --- | --- | --- |
| New payments | Reads bank SMS automatically | A one-time Shortcuts automation passes each bank SMS to the app |
| Past months | Last 180 days of SMS on first launch, plus statement import | Statement import |
| Cash / UPI Lite | Manual entry | Manual entry |

## Features

- Picks up UPI, card and bank transactions from bank SMS
- **Statement import:** bank PDF statements (password-protected ones too), bank CSV downloads, PhonePe PDF and Paytm CSV statements
- Monthly dashboard: spent, received, net and today's spend
- Spending by category, auto-guessed from the payee (Swiggy → Food, Jio → Bills)
- Change a category once and it's remembered for that payee
- "UPI only" filter, manual entry for cash
- Duplicates are skipped: the same payment from SMS and a statement is counted once (matched by UPI reference, or by same day, amount and direction)
- Ignores OTPs, collect requests, reminders, failed payments, promotions, and SMS from personal phone numbers
- Light and dark mode

## Get the Android APK without installing anything

Every push to `main` runs the tests and builds an installable APK on GitHub.

1. Open the **Actions** tab and click the latest **Test and build** run.
2. Download the **upitrack-apk** artifact and unzip it.
3. Copy `app-release.apk` to your Android phone and open it (allow "Install unknown apps" when asked).

You can also start a build from the Actions tab with **Run workflow**.

## Build locally

You need [Flutter](https://docs.flutter.dev/get-started/install) (stable).

```bash
git clone https://github.com/<your-username>/upitrack.git
cd upitrack

# One time: generates the standard platform files that aren't in the repo.
# Existing files (our manifest, MainActivity, Swift intent) aren't overwritten.
flutter create --platforms=android,ios --org com.piyush --project-name upitrack .

flutter pub get
flutter test
```

**Android:** `flutter run` with a phone connected (USB debugging on).

**iPhone** (needs a Mac with Xcode):

```bash
ruby scripts/setup_ios.rb      # adds the Shortcuts action to the Xcode project
open ios/Runner.xcworkspace    # Runner → Signing & Capabilities → pick your team
flutter run                    # with the iPhone connected
```

A free Apple ID can install the app on your own iPhone (it expires after 7 days). Sharing it through TestFlight or the App Store needs a paid Apple Developer account.

After the first `flutter create` you can commit the generated platform folders if you prefer to keep them in the repo.

## iPhone auto-tracking

iOS doesn't let apps read SMS, but the Shortcuts app can react to incoming messages. The app ships a Shortcuts action called **Log Bank SMS**. The in-app guide (menu → iPhone auto-tracking) walks the user through creating the automation:

1. Shortcuts → Automation → **+** → **Message**
2. Message Contains: `Rs` (and a second automation for `INR` if needed)
3. **Run Immediately**, notifications off
4. Add action **UPI Track → Log Bank SMS**, set Message to **Shortcut Input**

The action saves the message to the app's private folder; the app parses it with the same parser as Android the next time it opens. It only covers messages that arrive after setup, so statement import fills in the past. Needs iOS 17+ for automations that run without a confirmation tap; the app itself needs iOS 16+.

## Statement import

Menu → **Import statement**, then pick a file.

- **PDF:** bank statements and PhonePe statements. Locked PDFs ask for the password (usually customer ID or date of birth; the bank's email explains the format).
- **CSV:** net banking downloads (HDFC, SBI and others with Date / Narration / Withdrawal / Deposit columns) and Paytm exports.
- Excel files: open them and save as CSV first.

How rows are read: each transaction starts on a line with a date. Debit or credit is worked out from how the running balance changes (so it works whether the statement is oldest-first or newest-first), falling back to DR/CR or DEBIT/CREDIT labels. The payee is taken from the narration, e.g. `UPI-SWIGGY-SWIGGY.STORES@AXB-…` → `SWIGGY`.

## How it works

```
Android: SMS inbox ──► MainActivity.kt ─┐
iPhone:  Shortcuts ──► BankSmsIntent.swift ─┤
                                            ├─► SmsParser ──┐
Statements (PDF/CSV) ──► StatementReader ──► StatementParser ┤
                                                             ├─► Categorizer ─► SQLite ─► Dashboard
Manual entry ────────────────────────────────────────────────┘
```

| Path | What it does |
| --- | --- |
| `lib/parser/sms_parser.dart` | Amount, direction, payee, bank, account and UPI ref from a bank SMS. Pure Dart. |
| `lib/parser/statement_parser.dart` | Rows from statement text and CSV. Pure Dart. |
| `lib/parser/categorizer.dart` | Keyword-based category guess. |
| `lib/data/repository.dart` | Sync, import and duplicate matching. |
| `lib/data/db.dart` | SQLite tables: `txns`, `rules` (payee → category), `meta`. |
| `lib/data/statement_reader.dart` | Opens PDFs (with password) and CSVs. |
| `lib/data/shortcut_inbox.dart` | Reads messages saved by the iPhone Shortcuts action. |
| `android/.../MainActivity.kt` | Reads `content://sms/inbox` on a background thread. |
| `ios/Runner/BankSmsIntent.swift` | The "Log Bank SMS" Shortcuts action. |
| `scripts/setup_ios.rb` | Registers the Swift file in the Xcode project, sets iOS 16 minimum. |
| `lib/screens/` | Dashboard, details, manual entry, import flow, iPhone guide. |

## Adding a bank or fixing a missed transaction

Each bank words its SMS and statements differently. If something is missing or wrong:

1. Copy the SMS or a few statement lines and **anonymise them**: change names, account digits, UPI IDs and reference numbers.
2. Add a test in `test/sms_parser_test.dart` or `test/statement_parser_test.dart` with the values you expect.
3. Run `flutter test`, adjust the parser until it passes, and check the other tests still pass.

Pull requests with new formats are welcome. Never commit real, un-anonymised data.

## Publishing

**Google Play** restricts the SMS permission. Budget apps can use it under the **SMS-based money management** exception. You'll need to fill in the Permissions Declaration Form, record a demo video of a bank SMS becoming a transaction, make SMS tracking the main feature in the listing, publish a privacy policy saying SMS are processed only on the device, and sign with your own release key ([guide](https://docs.flutter.dev/deployment/android#sign-the-app)). Check the current policy before submitting.

**App Store:** no special permission is needed for the Shortcuts route. Explain the automation setup in the review notes.

## Licences

The app is MIT-licensed. PDF reading uses [`syncfusion_flutter_pdf`](https://pub.dev/packages/syncfusion_flutter_pdf), which is free under the Syncfusion Community License for individuals and companies under its revenue limit, and otherwise needs a commercial licence. Check its terms before shipping a commercial version.

## Limitations

- iPhone tracking only covers SMS received after the automation is set up; use statement import for earlier months.
- Payments without a bank SMS (often UPI Lite) need manual entry or a statement import.
- Unusual bank formats may need a test case and a parser tweak (see above).

## Roadmap ideas

- "Didn't catch this SMS?" screen that learns a new bank format on the phone
- Home-screen widget with today's spend
- Monthly budget per category with alerts
- Export to CSV
- Search and date-range filters

## License

[MIT](LICENSE)
