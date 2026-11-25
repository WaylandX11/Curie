import 'package:curie_windows/src/generated/build_info.dart';
import 'package:curie_windows/src/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows build is marked as alpha', () {
    expect(buildChannel, 'alpha');
    expect(displayVersion, '$buildStamp-alpha');
    expect(displayVersion, endsWith('-alpha'));
  });
}
