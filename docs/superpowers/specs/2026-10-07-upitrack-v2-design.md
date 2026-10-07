# UPI Track v2 — shared, synced, on every screen

Date: 2026-10-07
Status: approved design, awaiting implementation plan

## 1. Goal

Turn UPI Track from a single-phone app into one that a small circle of friends
and family can use on Android, iPhone and laptops, with every device of one
person showing the same data. No app store, no server run by us.

Plain English: you install it, your payments show up on your phone as they
happen, and the same list is waiting for you in a browser tab on your laptop.
Nothing is uploaded anywhere except a scrambled copy in your own Google Drive.

### In scope

- Phase 0: get the current app onto GitHub and onto a real phone.
- Phase 1: the fixes a shared app needs before other people use it.
- Phase 2: Google Drive sync with encryption, and a web build for laptops.

### Out of scope (later, separate specs)

- Phase 3 features: search and date filters, budgets, trends, CSV export,
  smarter handling of refunds and self-transfers, recurring payments.
- iCloud as a second sync provider.
- Desktop (Windows/Mac) builds. The web app covers laptops.
- Onboarding screens, home-screen widget, any server.
- iPhone distribution. Sharing to friends' iPhones needs TestFlight (paid
  Apple Developer account). That is a decision for the owner, not a code task;
  the iOS build keeps working either way.

## 2. Phase 0 — prove it works

1. Push the repo to GitHub. The existing workflow then runs the tests and
   builds `app-release.apk` on every push to `main`.
2. Install the APK on the owner's phone and let it read 180 days of SMS.
3. Note every payment it missed or got wrong. Those become test cases in
   `test/sms_parser_test.dart` before anything else is built.

Exit: the owner has used the app with real bank SMS for at least a day.

## 3. Phase 1 — safe to share

### 3.1 Duplicate bug in statement import

`TxnRepository.importStatement` builds a `Set` of `day|amount|direction` keys
from existing non-statement transactions and marks every statement row with a
matching key as a duplicate. Two ₹50 payments on one day with one SMS caught
drops both rows, losing one payment.

Fix: use a `Map<String, int>` of counts and decrement on each match; a row is
a duplicate only while the count is above zero. Covered by a repository test
(see §6).

### 3.2 Unhide

Hidden transactions cannot be brought back today.

- New screen "Hidden" (menu → Hidden): lists `hidden = 1` rows for all time,
  newest first, each with an Unhide button.
- `AppDb.unhide(id)` sets `hidden = 0` and `edit_ts = now` (see §4.3).

### 3.3 "Didn't catch this?" — unparsed bank SMS

Plain English: a bank SMS the app cannot read is kept in a list instead of
vanishing. The user can add it by hand, ignore it, or send an anonymised copy
to the developer.

- `SmsParser.looksLikeTransaction(address, body)` → `bool`. True when the
  sender passes `isLikelyBankSender`, the body is not matched by `_exclude`
  (OTP, promo, reminder, failed), it mentions an account, card or UPI (`_account` / `_upiWord`), and it contains either a currency amount
  (`_currencyAmount`) or a debit/credit word (`_debitWord` / `_creditWord`).
- During `syncSms` and `syncShortcutInbox`, every message where `parse`
  returns null but `looksLikeTransaction` is true is stored in a new table:

  ```sql
  CREATE TABLE unparsed(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    key TEXT NOT NULL UNIQUE,      -- 'sms:<id>' or 'shortcut:<file id>'
    sender TEXT NOT NULL,
    body TEXT NOT NULL,
    ts INTEGER NOT NULL,
    state TEXT NOT NULL DEFAULT 'open'   -- open | added | ignored
  )
  ```

  Device-local; not synced.
- Home screen: when `open` rows exist, a card "N messages we couldn't read"
  above the month switcher, tapping it opens the Unparsed screen.
- Unparsed screen, one tile per message (sender, date, first two lines of the
  body), three actions:
  - **Add**: opens the existing Add sheet pre-filled with the first amount
    found by `_currencyAmount` or `_verbAmount` and the message date; on save
    the transaction is stored with `source = 'manual'`, `raw = body`, and the
    row becomes `added`.
  - **Ignore**: row becomes `ignored`.
  - **Report**: `share_plus` share sheet with the anonymised body (§3.4) and
    the sender id, so the owner can turn it into a parser test case.
- Rows older than 90 days in state `ignored` or `added` are deleted on sync.

### 3.4 Anonymiser

`lib/parser/anonymise.dart`, pure Dart, tested.

- Any run of 4 or more digits → same number of `X`s, except amounts: a number
  directly preceded by `Rs`, `INR`, `₹`, or by `debited|credited (by|for|with|of)`
  is kept.
- UPI IDs (`_vpa` pattern) → `name@bank` with the local part replaced by
  `xxxx`, the handle kept (the handle is what the parser needs).
- Words of 3+ letters in Title Case or ALL CAPS that follow `to|from|by|at|trf to`
  (likely a person or merchant name) → `NAME`.
- Everything else is kept, because the parser is driven by structure words.

### 3.5 Live SMS notification (Android)

Plain English: the phone shows "₹250 to Swiggy · Food" the moment the bank
SMS arrives, instead of waiting for the app to be opened.

- `AndroidManifest.xml`: add `RECEIVE_SMS` and `POST_NOTIFICATIONS`
  permissions and a manifest-registered `SmsReceiver` for
  `android.provider.Telephony.SMS_RECEIVED`.
- `SmsReceiver.kt`: joins the PDUs into one body, then starts a background
  `FlutterEngine` running the Dart entrypoint `smsBackground` and passes
  `{address, body}` over a method channel `upitrack/sms_bg`. Uses
  `goAsync()` so the broadcast stays alive until Dart replies (bounded to
  10 s by Android; the parser is sub-millisecond).
- `lib/background/sms_background.dart`: `@pragma('vm:entry-point')
  void smsBackground()`. Parses with `SmsParser.parse`, reads the
  payee→category rules from the DB, and posts one notification via
  `flutter_local_notifications`: title `-₹250 to SWIGGY` (or `+₹500 from …`),
  body `Food · HDFC Bank •••1234`. Tap opens the app.
- **The background path never writes transactions.** The normal inbox sync
  on next open records the SMS, so there is no second key scheme and no
  duplicate risk. Consequence, deliberately accepted: other devices see a
  payment only after the phone app is next opened. If that bothers users, a
  periodic WorkManager sync is the upgrade.
- Permission flow: the existing permission card asks for SMS; on grant it
  also asks for `Permission.notification`. Notifications off → receiver still
  runs but shows nothing.
- Known limit, documented in README: vendor battery savers (Xiaomi, Vivo,
  Oppo) may block the receiver; the inbox sync on open still catches up.

### 3.6 Update check (Android)

No app store means no auto-update.

- Once per 24 h (`meta.update_checked_ms`), GET
  `https://api.github.com/repos/aksh0609/upitrack/releases/latest`. Compare
  `tag_name` (e.g. `v0.2.0`) with `package_info_plus` version using plain
  semver tuple comparison.
- Newer → a dismissible banner at the top of the home list: "Version 0.2.0 is
  available", button opens the release page in the browser (`url_launcher`).
  Dismissing hides that version only (`meta.update_dismissed = tag`).
- Not shown on web (always current) or iOS (TestFlight updates itself).
- CI: tagging `v*` creates a GitHub Release with the APK attached, so the
  release page is where friends download from.

## 4. Phase 2 — sync and web

### 4.1 How sync works (plain English)

Every device keeps its own full copy. When it syncs, it uploads a scrambled
snapshot of everything it knows into a hidden folder of the user's Google
Drive, and downloads the snapshots of the user's other devices. Payments are
only ever added (hiding is a flag), so merging is "put everything together";
for category changes and hiding, the most recent change wins.

### 4.2 Storage layout in Drive

Drive `appDataFolder`, scope `https://www.googleapis.com/auth/drive.appdata`
(non-sensitive; no Google verification required).

| File | Written by | Content |
| --- | --- | --- |
| `meta.json` | first device to set up sync | `{ "v": 1, "kdf": "pbkdf2-sha256", "iterations": 200000, "salt": "<base64 16 B>", "check": "<base64 AES-GCM of the ASCII string 'upitrack-key-ok'>" }` — plain text |
| `dev-<deviceId>.json.enc` | that device only | encrypted snapshot (§4.4) |

Each device writes only its own `dev-*` file, so there are no write
conflicts. A device replaces the whole file on upload (`files.update` with
media). `meta.json` is written once and never changed; "reset sync" deletes
every file in the folder.

### 4.3 Database changes (schema v3; v2 is Phase 1's `unparsed` table)

```sql
ALTER TABLE txns ADD COLUMN edit_ts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE rules ADD COLUMN ts INTEGER NOT NULL DEFAULT 0;
-- meta keys: device_id (UUID v4, generated once),
--            sync_dirty ('1' when local state changed since last upload),
--            seen_md5:<deviceId> (md5 of the last applied remote snapshot)
```

- `edit_ts` is **0 for every automatically inserted row** (SMS, statement,
  shortcut) and `now` only when the user changes category or hides/unhides.
  So an automatic import on another device can never overwrite a human
  correction.
- Manual entries: `edit_ts = now` at creation; key becomes
  `manual:<deviceId>:<micros>` so two devices can't collide.
- `rules.ts = now` on every `setCategoryForPayee`.
- Every write that changes txns or rules sets `sync_dirty = '1'`.

### 4.4 Snapshot format (before encryption)

```json
{
  "v": 1,
  "device": "<deviceId>",
  "exported_ms": 1760000000000,
  "txns": [ { ...Txn.toMap() fields..., "hidden": 0, "edit_ts": 0 } ],
  "rules": [ { "counterparty": "SWIGGY", "category": "Food", "ts": 1760000000000 } ]
}
```

`txns` includes hidden rows and `raw` (the original SMS), because the laptop
shows the "Original SMS" panel too. A snapshot is the device's whole table,
which after one merge round includes what it learned from other devices — so
if a device is wiped, its data survives in the others' snapshots.

Size: ~300 B per transaction → 10k transactions ≈ 3 MB plain, gzip before
encrypting (typically 5×). `ponytail:` whole-file snapshots; move to chunked
or append-only files if anyone passes ~50k transactions.

### 4.5 Merge algorithm

```
sync():
  if not signed in or no key: return
  files = drive.list(appDataFolder)
  for f in files where f.name starts with 'dev-' and f.name != mine:
      if f.md5Checksum == meta['seen_md5:<dev>']: continue
      snap = decrypt(download(f))
      apply(snap); meta['seen_md5:<dev>'] = f.md5Checksum
  if meta.sync_dirty == '1' or my file missing:
      upload(encrypt(gzip(snapshot())))
      meta.sync_dirty = '0'

apply(snap):   -- one SQLite transaction
  for t in snap.txns:
      local = SELECT by key
      if none: INSERT t (as is, including edit_ts, hidden)
      elif t.edit_ts > local.edit_ts: UPDATE category, hidden, edit_ts
  for r in snap.rules:
      local = SELECT by counterparty
      if none or r.ts > local.ts:
          UPSERT rule
          UPDATE txns SET category = r.category
            WHERE counterparty = r.counterparty AND is_debit = 1 AND edit_ts < r.ts
  if anything changed: meta.sync_dirty = '1'   -- so my snapshot carries it on
```

`apply` is idempotent and order-independent. The rule update leaves
per-transaction `edit_ts` untouched, so a later direct edit of one payment
still wins over the payee rule, matching how the app behaves locally.

Triggers: app start/resume, 5 s after any local change (debounced), pull to
refresh, and after a successful SMS/shortcut/statement sync. Failures (offline,
token expired) are silent except for a small "Last synced …" line under the
summary card and a warning icon on the menu; tapping it shows the error.

### 4.6 Encryption

- Passphrase → key: PBKDF2-HMAC-SHA256, 200 000 iterations, 16-byte random
  salt from `meta.json`, 32-byte output. Package `cryptography` (pure Dart,
  runs on web).
- Each file: 12-byte random nonce ‖ AES-256-GCM(ciphertext ‖ 16-byte tag).
- Key check: decrypting `meta.check` must yield `upitrack-key-ok`; otherwise
  "That passphrase doesn't match the one used on your other device."
- The derived key (not the passphrase) is stored locally with
  `flutter_secure_storage` (Keystore / Keychain / WebCrypto-wrapped storage
  on web).
- Forgotten passphrase: Settings → "Reset sync" deletes all files in the app
  data folder and lets the user pick a new passphrase; local data is kept and
  re-uploaded. Other devices get "sync was reset on another device" (their
  stored key fails the check) and must enter the new passphrase.

### 4.7 Sign-in and Drive access

- `google_sign_in` (7.x API) with `authorizationClient.authorizeScopes(
  ['https://www.googleapis.com/auth/drive.appdata'])`, and `googleapis`
  `DriveApi` over the authenticated client from
  `extension_google_sign_in_as_googleapis_auth`.
- Settings → "Sync with Google Drive": sign in → if `meta.json` exists ask
  for the existing passphrase, else ask to create one (twice) → first sync.
  "Sign out" clears the key and tokens but keeps local data.
- Owner setup (not code): a Google Cloud project with the Drive API enabled,
  OAuth consent screen published with only the `drive.appdata` scope, and
  three OAuth client IDs: Android (package `com.piyush.upitrack` + SHA-1 of
  the release keystore), iOS (bundle id), Web (origin
  `https://aksh0609.github.io`). Client IDs are not secrets and are committed.

### 4.8 Web build

Plain English: the same app, built for the browser and hosted free on GitHub
Pages. Friends open a link. No SMS on a laptop, so it shows the synced data and
imports statements.

- Database: `sqflite_common_ffi_web` (`databaseFactoryFfiWeb`) when `kIsWeb`,
  the existing `sqflite` otherwise. `dart run sqflite_common_ffi_web:setup`
  adds `sqflite_sw.js` and `sqlite3.wasm` to `web/`; they are committed.
- `dart:io` is removed from shared code: `ShortcutInbox` gets a conditional
  import (`shortcut_inbox_io.dart` / `shortcut_inbox_stub.dart` returning no
  messages); `Platform.isIOS` becomes `defaultTargetPlatform ==
  TargetPlatform.iOS && !kIsWeb`.
- Platform guards: SMS sync only on Android; shortcut inbox only on iOS;
  permission card only on Android; live-SMS and update banner only on
  Android. On web the home screen shows a "Sync with Google Drive" card
  until sync is set up.
- PDF extraction runs on the main thread on web (`compute` is a no-op there);
  the existing progress dialog covers the pause.
- `web/index.html` gets `<meta name="google-signin-client_id" …>`.
- CI: new job `flutter build web --release --base-href /upitrack/` and deploy
  to GitHub Pages on push to `main`.

### 4.9 Tests for Phase 2

- `test/sync/merge_test.dart`: pure functions over in-memory lists — union,
  edit wins by `edit_ts`, auto row (0) never beats an edit, rule application
  respects `edit_ts`, idempotent re-apply.
- `test/sync/crypto_test.dart`: encrypt → decrypt round-trip, wrong key fails
  the check, nonce never repeats across two encryptions.
- `test/data/repository_test.dart` using `sqflite_common_ffi`: the duplicate
  fix (§3.1), `apply(snapshot)` against a real SQLite file, `sync_dirty`
  bookkeeping.
- Drive calls sit behind a tiny `SyncStore` interface (`list`, `download`,
  `upload`, `delete`) with an in-memory fake for tests. One implementation
  (`DriveSyncStore`); the interface exists only so the sync logic is testable.

## 5. New files and dependencies

| Path | Purpose |
| --- | --- |
| `lib/parser/anonymise.dart` | §3.4 |
| `lib/background/sms_background.dart` | §3.5 Dart entrypoint |
| `android/.../SmsReceiver.kt` | §3.5 receiver |
| `lib/screens/unparsed_screen.dart`, `hidden_screen.dart`, `settings_screen.dart` | §3.3, §3.2, §4.7 |
| `lib/sync/sync_store.dart`, `drive_sync_store.dart`, `snapshot.dart`, `crypto.dart`, `sync_service.dart` | §4 |
| `lib/data/shortcut_inbox_io.dart`, `shortcut_inbox_stub.dart` | §4.8 |
| `lib/util/update_check.dart` | §3.6 |
| `web/` | Flutter web scaffold + sqflite worker files |

Dependencies added: `google_sign_in`, `googleapis`,
`extension_google_sign_in_as_googleapis_auth`, `cryptography`,
`flutter_secure_storage`, `sqflite_common_ffi_web`, `flutter_local_notifications`,
`share_plus`, `package_info_plus`, `url_launcher`, `http`, `uuid`.
Dev: `sqflite_common_ffi`.

## 6. Risks and limits (documented in README)

- Google sign-in on a sideloaded APK only works if the APK is signed with the
  keystore whose SHA-1 is registered. Debug builds need the debug SHA-1 added
  too.
- A forgotten passphrase means resetting sync; local data is never lost.
- Vendor battery savers can block the live-SMS receiver; opening the app
  still catches up from the inbox.
- Another device sees new payments only after the phone app has been opened
  (no background Drive upload in v2).
- Web storage is per browser profile; clearing site data clears the local
  copy, which sync restores.
- iPhone users need TestFlight to receive the app from the owner.

## 7. Order of work

1. Phase 0 (GitHub, install, collect real misses).
2. Phase 1 in this order: §3.1 duplicate fix + repository test harness
   (`sqflite_common_ffi`), §3.2 unhide, §3.3/§3.4 unparsed + anonymiser,
   §3.6 update check + release workflow, §3.5 live SMS.
3. Phase 2: schema v2 + `edit_ts` plumbing → snapshot + merge (pure) →
   crypto → `SyncStore` fake + `SyncService` → Drive store + sign-in UI →
   web build + Pages deploy → platform guards → README.
