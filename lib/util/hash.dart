/// Small stable hash (32-bit FNV-1a) as lowercase hex. The same text gives
/// the same value on Android, iPhone and the web, so keys built from it
/// still match after sync. The multiplication is split so it never exceeds
/// 2^53 on the web, where ints are doubles.
String fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    // h * 0x01000193 mod 2^32, with 0x01000193 = 2^24 + 0x193.
    h = (((h << 24) & 0xffffffff) + h * 0x193) & 0xffffffff;
  }
  return h.toRadixString(16);
}
