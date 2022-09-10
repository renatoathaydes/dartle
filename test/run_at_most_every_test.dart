import 'package:clock/clock.dart';
import 'package:dartle/dartle.dart';
import 'package:test/test.dart';

import 'cache_mock.dart';
import 'test_utils.dart';

final _invocation = taskInvocation('name');

void main() {
  group('RunAtMostEvery', () {
    test('always runs if never executed before', () async {
      var cache = CacheMock()
        ..invocationChanges = {
          _invocation.name: [false, false, true]
        };

      final condition = RunAtMostEvery(Duration(seconds: 10), cache);

      expect(await condition.shouldRun(_invocation), isTrue);
      expect(await condition.shouldRun(_invocation), isTrue);
      expect(await condition.shouldRun(_invocation), isTrue);
    });

    test('runs only after the period has passed', () async {
      var cache = CacheMock()
        ..invocationChanges = {
          _invocation.name: [false, false, false, false]
        }
        ..invocationTimes = {
          _invocation.name: DateTime.parse('2012-02-27 13:27:00')
        };

      final condition = RunAtMostEvery(Duration(seconds: 10), cache);

      final sameTimeAsLastInvocation = await withClock(
          Clock.fixed(DateTime.parse('2012-02-27 13:27:00')),
          () => condition.shouldRun(_invocation));

      expect(sameTimeAsLastInvocation, isFalse);

      final fiveSecondsAfterLastInvocation = await withClock(
          Clock.fixed(DateTime.parse('2012-02-27 13:27:05')),
          () => condition.shouldRun(_invocation));

      expect(fiveSecondsAfterLastInvocation, isFalse);

      final fifteenSecondsAfterLastInvocation = await withClock(
          Clock.fixed(DateTime.parse('2012-02-27 13:27:15')),
          () => condition.shouldRun(_invocation));

      expect(fifteenSecondsAfterLastInvocation, isTrue);

      final tenYearsAfterLastInvocation = await withClock(
          Clock.fixed(DateTime.parse('2022-02-27 13:27:15')),
          () => condition.shouldRun(_invocation));

      expect(tenYearsAfterLastInvocation, isTrue);
    });

    test('always runs if invocation changed', () async {
      var cache = CacheMock()
        ..invocationChanges = {
          _invocation.name: [true, true, true, true]
        }
        ..invocationTimes = {
          _invocation.name: DateTime.parse('2012-02-27 13:27:00')
        };

      final condition = RunAtMostEvery(Duration(seconds: 10), cache);

      final sameTimeAsLastInvocation = await withClock(
          Clock.fixed(DateTime.parse('2012-02-27 13:27:00')),
          () => condition.shouldRun(_invocation));

      expect(sameTimeAsLastInvocation, isTrue);

      final fiveSecondsAfterLastInvocation = await withClock(
          Clock.fixed(DateTime.parse('2012-02-27 13:27:05')),
          () => condition.shouldRun(_invocation));

      expect(fiveSecondsAfterLastInvocation, isTrue);

      final fifteenSecondsAfterLastInvocation = await withClock(
          Clock.fixed(DateTime.parse('2012-02-27 13:27:15')),
          () => condition.shouldRun(_invocation));

      expect(fifteenSecondsAfterLastInvocation, isTrue);

      final tenYearsAfterLastInvocation = await withClock(
          Clock.fixed(DateTime.parse('2022-02-27 13:27:15')),
          () => condition.shouldRun(_invocation));

      expect(tenYearsAfterLastInvocation, isTrue);
    });
  });
}
