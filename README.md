# UPI Track

An Android app that tracks payments from **every UPI app** (PhonePe, Google Pay, Paytm, BHIM, CRED, bank apps) without connecting to any of them.

Every UPI payment makes your bank send an SMS. UPI Track reads those bank SMS on your phone, turns them into a clean list of transactions, and shows where your money went each month. Nothing is uploaded: there is no server, no login and no internet permission in release builds.

## Features

- Automatically picks up UPI, card and bank transactions from bank SMS
- Monthly dashboard: spent, received, net and today's spend
- Spending by category, auto-guessed from the payee (Swiggy → Food, Jio → Bills)
- Change a category once and it's remembered for that payee
- "UPI only" filter
- Add cash or UPI Lite payments by hand
- Duplicate SMS are counted once (matched by UPI reference number)
- Ignores OTPs, collect requests, bill reminders, failed payments and promotions
- Ignores SMS from personal phone numbers, so nobody can fake a transaction by texting you
- Light and dark mode

## Get the APK without installing anything

Every push to `main` runs the tests and builds an installable APK on GitHub.

1. Open the **Actions** tab of this repo and click the latest **Test and build APK** run.
2. Download the **upitrack-apk** artifact at the bottom and unzip it.
3. Copy `app-release.apk` to your Android phone and open it (allow "Install unknown apps" when asked).

You can also start a build manually from the Actions tab with **Run workflow**.

## Build locally

You need [Flutter](https://docs.flutter.dev/get-started/install) (stable) and Android Studio or the Android SDK.

```bash
git clone https://github.com/<your-username>/upitrack.git
cd upitrack

# One time: generates the standard Android Gradle files that aren't in the repo.
# Existing files (our manifest and MainActivity) are not overwritten.
flutter create --platforms=android --org com.piyush --project-name upitrack .

flutter pub get
flutter test          # parser, categorizer and widget tests
flutter run           # with a phone connected (USB debugging on)
```

After the first `flutter create` you can commit the generated `android/` files if you prefer to keep them in the repo.

> SMS can only be read on a real phone or an emulator with SMS. Send a test bank-style SMS to an emulator from its extended controls (Phone → SMS), using an alphanumeric sender like `VM-HDFCBK`.

## How it works

```
Bank SMS inbox ──► MainActivity.kt ──► SmsParser ──► Categorizer ──► SQLite ──► Dashboard
                  (reads inbox via     (amount, debit/   (payee →       (on device,
                   a MethodChannel)     credit, payee,    category)      deduped by
                                        bank, ref)                       UPI ref)
```

| Path | What it does |
| --- | --- |
| `lib/parser/sms_parser.dart` | Extracts amount, direction, payee, bank, account and UPI ref from an SMS. Pure Dart. |
| `lib/parser/categorizer.dart` | Keyword-based category guess. |
| `lib/data/repository.dart` | Sync logic: reads new SMS since the last sync, parses, applies saved rules, stores. |
| `lib/data/db.dart` | SQLite tables: `txns`, `rules` (payee → category), `meta`. |
| `android/.../MainActivity.kt` | Reads `content://sms/inbox` on a background thread. |
| `lib/screens/` | Dashboard, transaction details and manual entry. |

The first launch reads the last 180 days of SMS. After that, each sync only reads messages since the last one, and the app re-checks automatically whenever you return to it.

## Adding a bank or fixing a missed SMS

Each bank words its SMS differently. If a transaction is missing or wrong:

1. Copy the SMS and **anonymise it**: change names, account digits, UPI IDs and reference numbers.
2. Add it as a test in `test/sms_parser_test.dart` with the values you expect.
3. Run `flutter test`, adjust the patterns in `sms_parser.dart` until it passes, and make sure the other tests still pass.
4. Add the bank's SMS sender code to `_banks` in `sms_parser.dart` if it isn't recognised.

Pull requests with new bank formats are welcome. Please never commit a real, un-anonymised SMS.

## Publishing on Google Play

Google Play restricts the SMS permission. Budget-tracking apps can use it under the **SMS-based money management** exception, but you must:

- Fill in the **Permissions Declaration Form** in Play Console, choosing that use case.
- Record a short demo video showing a bank SMS turning into a transaction in the app.
- Make SMS tracking the main feature in your store listing.
- Publish a privacy policy and Data Safety form that say SMS are processed only on the device.
- Sign the app with your own release key instead of the debug key the CI build uses ([guide](https://docs.flutter.dev/deployment/android#sign-the-app)).

Check the current policy in Play Console before submitting, as Google updates it periodically.

## Limitations

- **Android only.** iPhone doesn't allow apps to read SMS.
- Transactions that don't produce a bank SMS (often UPI Lite) need to be added by hand.
- The parser covers common formats from major Indian banks; less common banks may need a test case and a pattern tweak (see above).

## Roadmap ideas

- Home-screen widget with today's spend
- Monthly budget per category with alerts
- Export to CSV
- Search and date-range filters
- Automatic sync in the background when a new SMS arrives

## License

[MIT](LICENSE)
