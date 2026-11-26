import 'package:enroute/core/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatDistance', () {
    expect(formatDistance(350), '350 m');
    expect(formatDistance(2140), '2.1 km');
  });

  test('formatDuration', () {
    expect(formatDuration(20), '<1 min');
    expect(formatDuration(240), '4 min');
    expect(formatDuration(3900), '1 h 5 min');
    expect(formatDuration(7200), '2 h');
  });
}
