/// The OAuth **Web application** client id from the owner's Google Cloud
/// project (README → Owner setup). Android passes it as `serverClientId`;
/// the web app passes it as `clientId`, so its "Authorised JavaScript
/// origins" must list https://aksh0609.github.io, http://localhost and
/// http://localhost:8080.
/// Client ids are not secrets. Null = sign-in shows "not configured".
const String? kGoogleServerClientId = null;
