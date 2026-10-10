// Android: download a release APK and hand it to the system installer.
// Other platforms get a stub that throws; the home screen never calls it there.
export 'apk_installer_stub.dart' if (dart.library.io) 'apk_installer_io.dart';
