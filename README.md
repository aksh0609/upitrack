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
- **Didn't catch this?** A bank SMS the app can't read is kept in a "Not recognised" list: add it by hand, ignore it, or report an anonymised copy so the next version understands it
- **Instant notifications (Android):** "-₹250 to SWIGGY · Food" the moment the bank SMS arrives, even with the app closed
- Hidden payments can be restored from menu → Hidden
- Tells you when a new version is available (Android; the APK is installed by hand)
- **Merchants:** payees are grouped into merchants (Swiggy, Amazon, Flipkart, Myntra, Zomato…). The home screen shows your top merchants for the month; tap one for the last six months and every payment to it
- **Search** by payee or merchant
- **Accounts:** every bank account seen in your SMS becomes a chip (HDFC •••1234, SBI •••5678) that filters the whole month, no setup needed
- **Self transfers:** moving money between your own accounts is labelled "Self transfer" and left out of spent and received
- **Sync (optional):** sign in with Google and choose a passphrase; your payments, categories and hidden rows are encrypted on the phone and kept in a hidden folder of your own Google Drive, so a second phone shows the same data. Google cannot read it

## Get the Android APK

The latest release is on the [Releases page](https://github.com/aksh0609/upitrack/releases/latest): download `app-release.apk`, copy it to your Android phone and open it (allow "Install unknown apps" when asked). The app shows a banner when a newer release exists.

Every push to `main` also builds a test APK: open the **Actions** tab, pick the latest **Test and build** run and download the **upitrack-apk** artifact.

### Releasing a new version

1. Bump `version:` in `pubspec.yaml` (e.g. `0.2.0+2`).
2. Commit, then tag and push: `git tag v0.2.0 && git push origin main v0.2.0`.
3. The **Release** workflow builds the APK and attaches it to a GitHub Release. The tag must match the pubspec version or the workflow stops.

### One-time: a signing key for releases

Android only installs an update over an existing app when both are signed with the same key. Both workflows sign with your key when four repository secrets exist (so push builds and releases install over each other), and falls back to a throwaway debug key otherwise (fine for trying the app, but then an update needs an uninstall first).

1. Create a key once, somewhere safe (not in the repo):
   `keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
2. In the GitHub repo → Settings → Secrets and variables → Actions, add:
   - `KEYSTORE_BASE64`: the file, base64-encoded (`base64 -i upload-keystore.jks | pbcopy` on a Mac)
   - `KEYSTORE_PASSWORD` and `KEY_PASSWORD`: the passwords you chose
   - `KEY_ALIAS`: `upload`
3. Back up the `.jks` file and the passwords. Losing them means everyone must uninstall before the next update, and the Google sign-in for the planned Drive sync is tied to this key's SHA-1 (`keytool -list -v -keystore upload-keystore.jks`).

## Build locally

You need [Flutter](https://docs.flutter.dev/get-started/install) (stable).

```bash
git clone https://github.com/<your-username>/upitrack.git
cd upitrack

# The Android project is committed. iOS files are generated once:
flutter create --platforms=ios --org com.piyush --project-name upitrack .

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

The Android project is committed; the iOS folder is generated by `flutter create` and can be committed too once you've built it on a Mac.

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

## Sync between devices

Menu → **Sync** → *Sign in with Google*. The first device chooses a passphrase; every other device enters the same one. Sync runs when the app opens or resumes, a few seconds after any change, and on pull-to-refresh; a "Last synced" line sits under the summary card.

- What is stored: an encrypted copy of every transaction (including the original SMS text and hidden rows) and your payee rules, in Drive's app-data folder, which only this app can see. `meta.json` there is plain and holds only the salt and a key check.
- Encryption: PBKDF2-HMAC-SHA256 (200 000 rounds) turns the passphrase into an AES-256-GCM key on the device. The key, not the passphrase, is kept in the Android Keystore / iOS Keychain. Google never sees either.
- Merging: payments are only ever added. For category changes and hiding, the most recent human change wins; an automatic import on another device never overwrites your correction.
- Forgot the passphrase: *Reset sync* deletes the Drive files, you choose a new passphrase and this phone re-uploads everything. Other devices then ask for the new passphrase. Nothing on any phone is deleted.
- *Sign out* forgets the key on this phone and keeps your data.

### Owner setup (once, by whoever publishes the app)

Google sign-in needs a Google Cloud project — about ten minutes, plus one constant to paste in step 4:

1. [console.cloud.google.com](https://console.cloud.google.com) → New project (e.g. "UPI Track").
2. APIs & Services → Library → enable **Google Drive API**.
3. APIs & Services → OAuth consent screen → External → fill the app name and your email → Scopes → add `https://www.googleapis.com/auth/drive.appdata` only → Audience → Publish app (the `drive.appdata` scope is non-sensitive and needs no verification).
4. APIs & Services → Credentials → Create credentials → OAuth client ID → **Android**: package name `com.piyush.upitrack`, SHA-1 of the release keystore (`keytool -list -v -keystore upload-keystore.jks`, or `openssl x509 -in cert.pem -noout -fingerprint -sha1` on the PEM saved next to it). The current release key's SHA-1 is `F8:4D:00:30:A5:A4:77:9B:47:46:FE:3C:60:A0:8B:F4:1F:DD:91:0F`. Add a second Android client with the debug SHA-1 if you run debug builds. Also create a **Web application** client (no origins needed yet); paste its client id into `kGoogleServerClientId` in `lib/sync/oauth_ids.dart` — google_sign_in on Android requires it as the "server client id". Phase 2b adds a Web client for the GitHub Pages origin.

Client ids are not secrets; the Web client id is committed in code.

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
| `lib/parser/merchant.dart` | Payee string → merchant name. One line per merchant. |
| `lib/sync/` | Snapshot + merge rules (`snapshot.dart`, `merge.dart`), encryption (`crypto.dart`), the sync round (`sync_service.dart`), the Drive adapter (`drive_sync_store.dart`) and the controller the UI talks to (`sync_controller.dart`). |
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

1. On the phone, open the "Not recognised" card and tap **Report** on the message — it shares an anonymised copy (names, account numbers, references and UPI IDs masked). Or copy the SMS and anonymise it by hand.
2. Add a test in `test/sms_parser_test.dart` or `test/statement_parser_test.dart` with the values you expect.
3. Run `flutter test`, adjust the parser until it passes, and check the other tests still pass.

To add a merchant (so its payments are grouped and totalled), add one `('keyword', 'Name')` line to `merchantKeywords` in `lib/parser/merchant.dart`, longest keyword first, and a line to `test/parser/merchant_test.dart`.

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
- Instant notifications depend on Android delivering the SMS broadcast; some phones (Xiaomi, Vivo, Oppo) block it under battery saving. Opening the app still catches up from the inbox.
- Self transfers are detected by "same amount, same day, two different accounts of yours". A friend paying you back the exact amount you paid someone else, into a different account, on the same day, is mis-labelled — change its category to fix it.
- Statement rows carry no account, so they appear under "All" only and are never paired as self transfers.
- Sync needs the app to be opened: another device sees new payments only after the phone that received the SMS has run the app (no background upload).
- Google sign-in on a sideloaded APK works only when the APK is signed with the keystore whose SHA-1 is registered in the Google Cloud project; a build signed with another key gets a sign-in error.
- Clearing the app's data (or reinstalling without sync) loses local-only changes made since the last successful sync.
- Self transfers are paired on the phone that received both bank SMS. A debit seen on one phone and the matching credit seen on another are not paired after sync.

## Roadmap ideas

- Teach the "Not recognised" screen to learn a new bank format on the phone, instead of only reporting it
- Home-screen widget with today's spend
- Monthly budget per category with alerts
- Export to CSV
- Cross-month search and date-range filters

## License

[MIT](LICENSE)
