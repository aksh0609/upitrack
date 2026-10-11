/// The OAuth **Web application** client id from the owner's Google Cloud
/// project (README → Owner setup). Android passes it as `serverClientId`;
/// the web app passes it as `clientId`, so its "Authorised JavaScript
/// origins" must list https://aksh0609.github.io, http://localhost and
/// http://localhost:8080.
/// Client ids are not secrets. Null = sign-in shows "not configured".
// Stays nullable so a fork can set it back to null and get the
// "not configured" message instead of a crash.
// ignore: unnecessary_nullable_for_final_variable_declarations
const String? kGoogleServerClientId =
    '58884319880-fnkuorieg0qn8j4d7mrnjfobq3dpi6b6.apps.googleusercontent.com';

/// The OAuth **iOS** client id for bundle id `com.akshay.upitrack` from the
/// same Google Cloud project (README → Owner setup). Its reversed form also
/// goes into ios/Runner/Info.plist as a URL scheme. Null = sign-in on an
/// iPhone shows "not configured".
const String? kGoogleIosClientId = null;
