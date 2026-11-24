import 'dart:io';

import 'package:curie/src/generated/build_info.dart';
import 'package:curie/src/services/user_agent.dart';
import 'package:curie/src/services/xray.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeXray extends Xray {
  @override
  Future<String> version() async => 'Xray 1.8.6';
}

void main() {
  test('current user agent takes the core version from libXray', () async {
    expect(
      await currentUserAgent(xray: _FakeXray()),
      'Curie/$buildStamp/1.8.6/${Platform.operatingSystem}',
    );
  });

  test('user agent has app, Xray core and OS parts', () {
    expect(
      formatUserAgent(
        appVersion: '26.11.24.1513',
        xrayVersion: 'Xray 1.8.6',
        platform: 'android',
      ),
      'Curie/26.11.24.1513/1.8.6/android',
    );
  });

  test('missing core version falls back to the bundled libXray version', () {
    expect(
      formatUserAgent(
        appVersion: '26.11.24.1513',
        xrayVersion: '',
        platform: 'ios',
      ),
      'Curie/26.11.24.1513/v26.11.9/ios',
    );
    expect(
      formatUserAgent(
        appVersion: '',
        xrayVersion: '1.8.6',
        platform: 'android',
      ),
      'Curie/0.1/1.8.6/android',
    );
  });
}
