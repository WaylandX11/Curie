import 'package:curie_windows/src/services/core_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 25, 12, 0);

  test('old Xray log lines are dropped, continuation lines are kept', () {
    final kept = CoreLog.applyRetention(
      [
        '2026/11/25 10:00:00 [Warning] old entry',
        '2026/11/25 11:30:00 [Error] fresh entry',
        '  at some.address',
      ],
      retention: const Duration(hours: 1),
      now: now,
    );

    expect(kept, [
      '2026/11/25 11:30:00 [Error] fresh entry',
      '  at some.address',
    ]);
  });

  test('only the freshest bytes survive the size cap', () {
    final kept = CoreLog.applyRetention(
      ['first', 'second', 'third'],
      retention: const Duration(hours: 24),
      now: now,
      maxBytesLimit: 12, // 'second\nthird' (перевод только между строками)
    );

    expect(kept, ['second', 'third']);
  });
}
