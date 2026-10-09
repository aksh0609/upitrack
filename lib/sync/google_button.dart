// Google's own sign-in button. The web plugin only signs in through it;
// other platforms use `GoogleAuth.signIn()` and never render this.
export 'google_button_stub.dart' if (dart.library.js_interop) 'google_button_web.dart';
