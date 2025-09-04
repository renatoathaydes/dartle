import 'package:dartle/src/_tasks_info.dart';
import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';

void main() {
  group('computeDependenciesCount', () {
    for (final ex in [
      (invoked: 0, defaults: 1, executables: 0, upToDate: 1, expected: 0),
      (invoked: 1, defaults: -1, executables: 1, upToDate: 0, expected: 0),
      (invoked: 1, defaults: -1, executables: 2, upToDate: 0, expected: 1),
      (invoked: 10, defaults: -1, executables: 3, upToDate: 20, expected: 13),
      (invoked: 0, defaults: 10, executables: 3, upToDate: 20, expected: 13),
    ]) {
      test('example $ex', () {
        expect(
          computeDependenciesCount(
            invoked: ex.invoked,
            defaults: ex.defaults,
            executables: ex.executables,
            upToDate: ex.upToDate,
          ),
          equals(ex.expected),
        );
      });
    }
  });
}
