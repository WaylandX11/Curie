import 'dart:convert';

import 'package:curie/src/services/traffic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses v26 /debug/vars shape and skips service outbounds', () {
    // Xray 26.x кладёт счётчики в stats.outbound.<tag>, рядом с inbound/user;
    // observatory и прочие expvar-поля не должны мешать разбору.
    final body = jsonEncode({
      'stats': {
        'inbound': {
          'tun': {'uplink': 10, 'downlink': 20},
        },
        'outbound': {
          'proxy': {'uplink': 1000, 'downlink': 2000},
          'proxy-2': {'uplink': 500, 'downlink': 700},
          'direct': {'uplink': 9999, 'downlink': 9999},
          'dns-out': {'uplink': 50, 'downlink': 50},
          'block': {'uplink': 30, 'downlink': 40},
        },
        'user': {},
      },
      'observatory': {},
    });

    final total = TrafficCounters.total(body);
    expect(total.up, 1500);
    expect(total.down, 2700);
  });

  test('malformed metrics do not throw', () {
    expect(TrafficCounters.total('not json').up, 0);
    expect(TrafficCounters.total('{}').down, 0);
    expect(TrafficCounters.total('{"stats":[]}').up, 0);
  });

  test('UI has one total speed instead of two arrows', () {
    expect(const TrafficSample(up: 100, down: 250).total, 350);
    expect(const TrafficSample().total, 0);
  });
}
