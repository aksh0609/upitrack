import 'package:flutter_test/flutter_test.dart';
import 'package:upitrack/util/hash.dart';

void main() {
  test('fnv1a matches the 32-bit FNV-1a reference values', () {
    expect(fnv1a(''), '811c9dc5');
    expect(fnv1a('a'), 'e40c292c');
    expect(fnv1a('foobar'), 'bf9cf968');
  });
}
