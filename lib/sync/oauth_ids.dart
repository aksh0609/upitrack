/// OAuth client ids are not secrets (spec §4.7). Android's google_sign_in 7
/// needs the WEB client id as `serverClientId`; see README "Owner setup".
/// Null until the owner creates the client — sign-in then fails fast with a
/// clear message instead of a cryptic Credential Manager error.
const String? kGoogleServerClientId = null;
