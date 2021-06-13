import 'package:dartle/src/dart/_dart_tests.dart';
import 'package:test/test.dart';

void main() {
  test('JsonReporter can log test events - single thread', () {
    final lines = <String>[];
    final reporter = JsonReporter(lines.add);
    reporter(
        '{"test":{"id":1,"name":"example test","suiteID":0,"groupIDs":[],"metadata":{"skip":false}},"type":"testStart","time":2}');
    reporter(
        '{"type": "testDone", "testID": 1, "result": "success", "hidden": false, "skipped": false, "time": 15928}');
    reporter.close();

    expect(
        lines,
        equals([
          equals('\n'),
          // clears line first because previous line could've been the status line
          equals(Ansi.clearLine),
          equals('T0   - example test\n'),
          equals('0      OK, 0      FAILED, 0      SKIPPED'),
          // start second event
          equals(Ansi.clearLine),
          equals(Ansi.moveUp),
          equals(Ansi.clearLine),
          equals('T0   - IDLE\n'),
          equals('1      OK, 0      FAILED, 0      SKIPPED'),
          equals(Ansi.clearLine),
          equals(Ansi.moveUp),
          equals(Ansi.clearLine),
          matches(
              'Tests finished in\\s+\\d+ ms\n1      OK, 0      FAILED, 0      SKIPPED\n'),
        ]));
  });
  test('JsonReporter can log test events - three threads', () {
    final lines = <String>[];
    final reporter = JsonReporter(lines.add);
    reporter(
        '{"test":{"id":1,"name":"example test","suiteID":0,"groupIDs":[],"metadata":{"skip":false}},"type":"testStart","time":2}');
    reporter(
        '{"test":{"id":2,"name":"other test","suiteID":0,"groupIDs":[],"metadata":{"skip":false}},"type":"testStart","time":2}');
    reporter(
        '{"type": "testDone", "testID": 1, "result": "success", "hidden": false, "skipped": false, "time": 4}');
    reporter(
        '{"test":{"id":3,"name":"last test","suiteID":0,"groupIDs":[],"metadata":{"skip":false}},"type":"testStart","time":5}');
    reporter(
        '{"type": "testDone", "testID": 3, "result": "success", "hidden": false, "skipped": false, "time": 6}');
    reporter(
        '{"type": "testDone", "testID": 2, "result": "success", "hidden": false, "skipped": false, "time": 7}');
    reporter.close();
    expect(
        lines,
        equals([
          equals('\n'),
          // clears line first because previous line could've been the status line
          equals(Ansi.clearLine),
          equals('T0   - example test\n'),
          equals('0      OK, 0      FAILED, 0      SKIPPED'),
          // start second event
          equals(Ansi.clearLine),
          equals(Ansi.moveUp),
          equals(Ansi.clearLine),
          equals('T0   - example test\n'),
          equals('T1   - other test\n'),
          equals('0      OK, 0      FAILED, 0      SKIPPED'),
          // example test is done
          equals(Ansi.clearLine),
          equals(Ansi.moveUp),
          equals(Ansi.clearLine),
          equals(Ansi.moveUp),
          equals(Ansi.clearLine),
          equals('T0   - IDLE\n'),
          equals('T1   - other test\n'),
          equals('1      OK, 0      FAILED, 0      SKIPPED'),
          // last test starts
          equals(Ansi.clearLine),
          equals(Ansi.moveUp),
          equals(Ansi.clearLine),
          equals(Ansi.moveUp),
          equals(Ansi.clearLine),
          equals('T0   - last test\n'),
          equals('T1   - other test\n'),
          equals('1      OK, 0      FAILED, 0      SKIPPED'),
          // last test done
          equals(Ansi.clearLine),
          equals(Ansi.moveUp),
          equals(Ansi.clearLine),
          equals(Ansi.moveUp),
          equals(Ansi.clearLine),
          equals('T0   - IDLE\n'),
          equals('T1   - other test\n'),
          equals('2      OK, 0      FAILED, 0      SKIPPED'),
          // second test done
          equals(Ansi.clearLine),
          equals(Ansi.moveUp),
          equals(Ansi.clearLine),
          equals(Ansi.moveUp),
          equals(Ansi.clearLine),
          equals('T0   - IDLE\n'),
          equals('T1   - IDLE\n'),
          equals('3      OK, 0      FAILED, 0      SKIPPED'),
          // close
          equals(Ansi.clearLine),
          equals(Ansi.moveUp),
          equals(Ansi.clearLine),
          equals(Ansi.moveUp),
          equals(Ansi.clearLine),
          matches(
              'Tests finished in\\s+\\d+ ms\n3      OK, 0      FAILED, 0      SKIPPED\n'),
        ]));
  });
}
