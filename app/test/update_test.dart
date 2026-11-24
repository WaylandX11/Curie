import 'package:curie/src/services/update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses tag, notes and the four APK assets', () {
    final release = GithubUpdate.parseRelease({
      'tag_name': 'v26.11.24.1410-alpha',
      'html_url': 'https://github.com/WaylandX11/Curie/releases/tag/x',
      'body': 'новая версия',
      'assets': [
        {'name': 'curie-v26-universal.apk', 'browser_download_url': 'u'},
        {'name': 'curie-v26-arm64.apk', 'browser_download_url': 'a64'},
        {'name': 'curie-v26-arm32.apk', 'browser_download_url': 'a32'},
        {'name': 'curie-v26-x64.apk', 'browser_download_url': 'x64'},
        {
          'name': 'curie-v26-universal.apk.sha256',
          'browser_download_url': 'bad',
        },
      ],
    });

    expect(release.version, '26.11.24.1410');
    expect(release.tag, 'v26.11.24.1410-alpha');
    expect(release.notes, 'новая версия');
    expect(release.assets.length, 4);
    expect(release.downloadUrlFor('arm64-v8a'), 'a64');
    expect(release.downloadUrlFor('armeabi-v7a'), 'a32');
    expect(release.downloadUrlFor('x86_64'), 'x64');
    expect(release.downloadUrlFor('riscv64'), 'u');
  });

  test('missing split falls back to universal, then to release page', () {
    final release = GithubUpdate.parseRelease({
      'tag_name': 'v26.11.24.1410',
      'html_url': 'page',
      'assets': [
        {'name': 'curie-universal.apk', 'browser_download_url': 'u'},
      ],
    });
    expect(release.downloadUrlFor('arm64-v8a'), 'u');

    final empty = GithubUpdate.parseRelease({
      'tag_name': 'v26.11.24.1410',
      'html_url': 'page',
    });
    expect(empty.downloadUrlFor('arm64-v8a'), 'page');
  });

  test('version comparison ignores the release suffix', () {
    expect(GithubUpdate.isNewer('26.11.24.1410', '26.11.24.1310'), isTrue);
    expect(GithubUpdate.isNewer('26.11.25.0900', '26.11.24.2359'), isTrue);
    expect(GithubUpdate.isNewer('26.11.24.1310', '26.11.24.1310'), isFalse);
    expect(GithubUpdate.isNewer('26.11.24.1230', '26.11.24.1310'), isFalse);
    expect(
      GithubUpdate.isNewer('26.11.24.1410-alpha', '26.11.24.1310'),
      isTrue,
    );
  });
}
