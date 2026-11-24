import 'package:curie/src/models/app_info.dart';
import 'package:curie/src/services/apps.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('user apps come first, alphabetically inside the group', () {
    final apps = [
      const AppInfo(packageName: 'com.a', label: 'Alpha', system: true),
      const AppInfo(packageName: 'com.z', label: 'Zeta'),
      const AppInfo(packageName: 'com.b', label: 'Beta'),
      const AppInfo(packageName: 'com.g', label: 'Gamma', system: true),
    ];

    Apps.sortApps(apps);

    expect(apps.map((app) => app.label).toList(), [
      'Beta',
      'Zeta',
      'Alpha',
      'Gamma',
    ]);
  });

  test('an app without a launcher icon still parses', () {
    final app = AppInfo.fromMap({
      'package': 'com.google.android.projection.gearhead',
      'label': 'Android Auto',
      'system': true,
    });

    expect(app.packageName, 'com.google.android.projection.gearhead');
    expect(app.label, 'Android Auto');
    expect(app.system, isTrue);
  });
}
