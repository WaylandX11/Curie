import 'package:curie/src/services/update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses tag, notes and the universal APK', () {
    final release = GithubUpdate.parseRelease({
      'tag_name': 'v26.11.24.1513-alpha',
      'html_url': 'https://github.com/WaylandX11/Curie/releases/tag/x',
      'body': 'новая версия',
      'assets': [
        {
          'name': 'curie-v26.11.24.1513-alpha-universal.apk',
          'browser_download_url': 'u',
        },
        {
          'name': 'curie-v26.11.24.1513-alpha-arm64.apk',
          'browser_download_url': 'a64',
        },
        {
          'name': 'curie-v26.11.24.1513-alpha-universal.apk.sha256',
          'browser_download_url': 'bad',
        },
      ],
    });

    expect(release.version, '26.11.24.1513');
    expect(release.tag, 'v26.11.24.1513-alpha');
    expect(release.notes, 'новая версия');
    expect(release.downloadUrl, 'u');
  });

  test('falls back to the release page when there is no APK asset', () {
    final release = GithubUpdate.parseRelease({
      'tag_name': 'v26.11.24.1513',
      'html_url': 'page',
      'assets': [
        {
          'name': 'curie-v26.11.24.1513-arm64.apk',
          'browser_download_url': 'a64',
        },
      ],
    });
    expect(release.downloadUrl, 'page');

    final empty = GithubUpdate.parseRelease({
      'tag_name': 'v26.11.24.1513',
      'html_url': 'page',
    });
    expect(empty.downloadUrl, 'page');
  });

  test('version comparison ignores the release suffix', () {
    expect(GithubUpdate.isNewer('26.11.24.1513', '26.11.24.1430'), isTrue);
    expect(GithubUpdate.isNewer('26.11.25.0900', '26.11.24.2359'), isTrue);
    expect(GithubUpdate.isNewer('26.11.24.1513', '26.11.24.1513'), isFalse);
    expect(GithubUpdate.isNewer('26.11.24.1430', '26.11.24.1513'), isFalse);
    expect(
      GithubUpdate.isNewer('26.11.24.1513-alpha', '26.11.24.1430'),
      isTrue,
    );
  });
}
