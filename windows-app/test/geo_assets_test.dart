import 'dart:convert';
import 'dart:io';

import 'package:curie_windows/src/models/settings.dart';
import 'package:curie_windows/src/models/subscription.dart';
import 'package:curie_windows/src/services/geo_assets.dart';
import 'package:curie_windows/src/services/xray_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    GeoAssets.directoryOverride = null;
    GeoAssets.fetchOverride = null;
    GeoAssets.pickOverride = null;
    GeoAssets.busy.value = false;
    GeoAssets.progress.value = const {};
  });

  test('geo settings migrate on and clamp the interval', () {
    final migrated = Settings.fromJson(<String, dynamic>{
      'defaultsRevision': 2,
      'geoAssetsUpdateHours': 999,
    });
    expect(migrated.geoAssetsAutoUpdate, isTrue);
    expect(migrated.geoAssetsWifiOnly, isTrue);
    expect(migrated.geoAssetsRestartXray, isTrue);
    expect(migrated.geoAssetsUpdateHours, 168);
    expect(migrated.geoipUrl, Settings.defaultGeoipUrl);

    final custom = Settings.fromJson(<String, dynamic>{
      'defaultsRevision': 3,
      'geoAssetsUpdateHours': 0,
      'geoipUrl': 'https://example.com/my-geoip.dat',
    });
    expect(custom.geoAssetsUpdateHours, 1);
    expect(custom.geoipUrl, 'https://example.com/my-geoip.dat');
  });

  test('detects only geo rules that need DAT files', () {
    expect(GeoAssets.containsGeoRules('"geoip:ru"'), isTrue);
    expect(GeoAssets.containsGeoRules('"geosite:category-ads"'), isTrue);
    expect(GeoAssets.containsGeoRules('regexp:.*\\.ru\$'), isFalse);
    expect(GeoAssets.containsGeoRules('domain:example.com'), isFalse);
  });

  test('detects geo rules inside base64 subscriptions', () {
    final plain =
        '{"routing":{"rules":[{"outboundTag":"proxy","domain":'
        '["geosite:category-ads"]}]}}';
    final body = base64.encode(utf8.encode(plain));
    expect(GeoAssets.containsGeoRules(body), isTrue);
  });

  test('download progress is reported per file and cleared afterwards', () {
    GeoAssets.reportProgress(GeoAssetKind.geoip, 5, 10);
    GeoAssets.reportProgress(GeoAssetKind.geosite, 7, 0);
    expect(GeoAssets.progress.value[GeoAssetKind.geoip], 0.5);
    expect(GeoAssets.progress.value[GeoAssetKind.geosite], 0.0);

    GeoAssets.clearProgress(GeoAssetKind.geoip);
    expect(GeoAssets.progress.value.containsKey(GeoAssetKind.geoip), isFalse);
    expect(GeoAssets.progress.value.containsKey(GeoAssetKind.geosite), isTrue);
  });

  test('validates a minimal protobuf container and rejects HTML', () {
    final valid = <int>[
      0x0a,
      0x08,
      0x0a,
      0x06,
      0x0c,
      0x72,
      0x75,
      0x73,
      0x73,
      0x69,
      0x61,
      0x01,
      0x02,
    ];
    expect(GeoAssets.isValidBytes(GeoAssetKind.geoip, valid), isTrue);
    expect(
      GeoAssets.isValidBytes(
        GeoAssetKind.geosite,
        utf8.encode('<html>403 Forbidden</html>'),
      ),
      isFalse,
    );
    expect(GeoAssets.isValidBytes(GeoAssetKind.geoip, const []), isFalse);
  });

  test('proxy bypass is direct without a tunnel', () {
    expect(GeoAssets.proxyFor(0), 'DIRECT');
    expect(GeoAssets.proxyFor(1080), 'PROXY 127.0.0.1:1080');
  });

  test('asset directory is private and created on demand', () async {
    final root = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}curie-geo-test',
    );
    if (await root.exists()) await root.delete(recursive: true);
    GeoAssets.directoryOverride = root.path;
    final dir = await GeoAssets.assetDirectory();
    expect(dir, endsWith('geo'));
    expect(await Directory(dir).exists(), isTrue);
    await root.delete(recursive: true);
  });

  test('build config carries geo asset directory into env', () {
    final config = json.decode(
      buildXrayConfig(
        outbounds: const [],
        settings: const Settings(),
        geoAssetDir: '/data/user/0/io.github.waylandx11.curie/geo',
      ),
    ) as Map<String, dynamic>;
    final env = config['env'] as Map<String, dynamic>;
    expect(
      env['xray.location.asset'],
      '/data/user/0/io.github.waylandx11.curie/geo',
    );
  });

  test('subscription flag survives JSON round trip', () {
    final profile = Subscription(title: 'x', url: 'https://example.com');
    final flagged = profile.copyWith(requiresGeoAssets: true);
    expect(Subscription.fromJson(flagged.toJson()).requiresGeoAssets, isTrue);
  });
}
