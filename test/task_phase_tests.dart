import 'dart:async';

import 'package:dartle/dartle.dart';
import 'package:test/test.dart';

void main() {
  group('TaskPhase', () {
    test('builtInPhases', () {
      expect(
        TaskPhase.builtInPhases,
        equals([TaskPhase.setup, TaskPhase.build, TaskPhase.tearDown]),
      );
    });
    test('currentZoneTaskPhases', () {
      expect(
        TaskPhase.currentZoneTaskPhases,
        equals([TaskPhase.setup, TaskPhase.build, TaskPhase.tearDown]),
      );
    });
    test('can create custom phases', () {
      // do not touch the root zone phases
      runZoned(
        () {
          final c1 = TaskPhase.custom(50, 'custom1');
          final c2 = TaskPhase.custom(150, 'custom2');
          expect(
            TaskPhase.currentZoneTaskPhases,
            equals([
              c1,
              TaskPhase.setup,
              c2,
              TaskPhase.build,
              TaskPhase.tearDown,
            ]),
          );
        },
        zoneValues: {
          TaskPhase.zonePhasesKey: [...TaskPhase.builtInPhases],
        },
      );

      // make sure the root zone was not affected.
      expect(
        TaskPhase.currentZoneTaskPhases,
        equals([TaskPhase.setup, TaskPhase.build, TaskPhase.tearDown]),
      );
    });
    test('isBefore', () {
      expect(TaskPhase.setup.isBefore(TaskPhase.setup), isFalse);
      expect(TaskPhase.setup.isBefore(TaskPhase.build), isTrue);
      expect(TaskPhase.setup.isBefore(TaskPhase.tearDown), isTrue);
      expect(TaskPhase.build.isBefore(TaskPhase.setup), isFalse);
      expect(TaskPhase.build.isBefore(TaskPhase.build), isFalse);
      expect(TaskPhase.build.isBefore(TaskPhase.tearDown), isTrue);
      expect(TaskPhase.tearDown.isBefore(TaskPhase.setup), isFalse);
      expect(TaskPhase.tearDown.isBefore(TaskPhase.build), isFalse);
      expect(TaskPhase.tearDown.isBefore(TaskPhase.tearDown), isFalse);
    });
    test('isAfter', () {
      expect(TaskPhase.setup.isAfter(TaskPhase.setup), isFalse);
      expect(TaskPhase.setup.isAfter(TaskPhase.build), isFalse);
      expect(TaskPhase.setup.isAfter(TaskPhase.tearDown), isFalse);
      expect(TaskPhase.build.isAfter(TaskPhase.setup), isTrue);
      expect(TaskPhase.build.isAfter(TaskPhase.build), isFalse);
      expect(TaskPhase.build.isAfter(TaskPhase.tearDown), isFalse);
      expect(TaskPhase.tearDown.isAfter(TaskPhase.setup), isTrue);
      expect(TaskPhase.tearDown.isAfter(TaskPhase.build), isTrue);
      expect(TaskPhase.tearDown.isAfter(TaskPhase.tearDown), isFalse);
    });
  });
}
