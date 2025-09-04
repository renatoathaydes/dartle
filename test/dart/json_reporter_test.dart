import 'package:dartle/src/_log.dart';
import 'package:dartle/src/dart/_dart_tests.dart';
import 'package:test/test.dart';

void main() {
  test('JsonReporter can log test events - single thread, color log', () {
    final lines = <String>[];
    final reporter = JsonReporter(lines.add);
    reporter(
      '{"test":{"id":1,"name":"example test","suiteID":0,"groupIDs":[],"metadata":{"skip":false}},"type":"testStart","time":2}',
    );
    reporter(
      '{"type": "testDone", "testID": 1, "result": "success", "hidden": false, "skipped": false, "time": 15928}',
    );
    reporter.close();

    expect(
      lines,
      equals([
        equals('\n'),
        // clears line first because previous line could've been the status line
        equals(Ansi.clearLine),
        equals('T0   - ${style('example test', LogStyle.bold)}\n'),
        equals(
          colorize('0      OK, 0      FAILED, 0      SKIPPED', LogColor.green),
        ),
        // start second event
        equals(Ansi.clearLine),
        equals(Ansi.moveUp),
        equals(Ansi.clearLine),
        equals('T0   - IDLE\n'),
        equals(
          colorize('1      OK, 0      FAILED, 0      SKIPPED', LogColor.green),
        ),
        equals(Ansi.clearLine),
        equals(Ansi.moveUp),
        equals(Ansi.clearLine),
        matches('Tests finished in\\s+\\d+ ms\n.*'),
      ]),
    );
  });
  test('JsonReporter can log test events - three threads', () {
    final lines = <String>[];
    final reporter = JsonReporter(lines.add);
    reporter(
      '{"test":{"id":1,"name":"example test","suiteID":0,"groupIDs":[],"metadata":{"skip":false}},"type":"testStart","time":2}',
    );
    reporter(
      '{"test":{"id":2,"name":"other test","suiteID":0,"groupIDs":[],"metadata":{"skip":false}},"type":"testStart","time":2}',
    );
    reporter(
      '{"type": "testDone", "testID": 1, "result": "success", "hidden": false, "skipped": false, "time": 4}',
    );
    reporter(
      '{"test":{"id":3,"name":"last test","suiteID":0,"groupIDs":[],"metadata":{"skip":false}},"type":"testStart","time":5}',
    );
    reporter(
      '{"type": "testDone", "testID": 3, "result": "success", "hidden": false, "skipped": false, "time": 6}',
    );
    reporter(
      '{"type": "testDone", "testID": 2, "result": "success", "hidden": false, "skipped": false, "time": 7}',
    );
    reporter.close();
    expect(
      lines,
      equals([
        equals('\n'),
        // clears line first because previous line could've been the status line
        equals(Ansi.clearLine),
        equals('T0   - ${style('example test', LogStyle.bold)}\n'),
        equals(
          colorize('0      OK, 0      FAILED, 0      SKIPPED', LogColor.green),
        ),
        // start second event
        equals(Ansi.clearLine),
        equals(Ansi.moveUp),
        equals(Ansi.clearLine),
        equals('T0   - ${style('example test', LogStyle.bold)}\n'),
        equals('T1   - ${style('other test', LogStyle.bold)}\n'),
        equals(
          colorize('0      OK, 0      FAILED, 0      SKIPPED', LogColor.green),
        ),
        // example test is done
        equals(Ansi.clearLine),
        equals(Ansi.moveUp),
        equals(Ansi.clearLine),
        equals(Ansi.moveUp),
        equals(Ansi.clearLine),
        equals('T0   - IDLE\n'),
        equals('T1   - ${style('other test', LogStyle.bold)}\n'),
        equals(
          colorize('1      OK, 0      FAILED, 0      SKIPPED', LogColor.green),
        ),
        // last test starts
        equals(Ansi.clearLine),
        equals(Ansi.moveUp),
        equals(Ansi.clearLine),
        equals(Ansi.moveUp),
        equals(Ansi.clearLine),
        equals('T0   - ${style('last test', LogStyle.bold)}\n'),
        equals('T1   - ${style('other test', LogStyle.bold)}\n'),
        equals(
          colorize('1      OK, 0      FAILED, 0      SKIPPED', LogColor.green),
        ),
        // last test done
        equals(Ansi.clearLine),
        equals(Ansi.moveUp),
        equals(Ansi.clearLine),
        equals(Ansi.moveUp),
        equals(Ansi.clearLine),
        equals('T0   - IDLE\n'),
        equals('T1   - ${style('other test', LogStyle.bold)}\n'),
        equals(
          colorize('2      OK, 0      FAILED, 0      SKIPPED', LogColor.green),
        ),
        // second test done
        equals(Ansi.clearLine),
        equals(Ansi.moveUp),
        equals(Ansi.clearLine),
        equals(Ansi.moveUp),
        equals(Ansi.clearLine),
        equals('T0   - IDLE\n'),
        equals('T1   - IDLE\n'),
        equals(
          colorize('3      OK, 0      FAILED, 0      SKIPPED', LogColor.green),
        ),
        // close
        equals(Ansi.clearLine),
        equals(Ansi.moveUp),
        equals(Ansi.clearLine),
        equals(Ansi.moveUp),
        equals(Ansi.clearLine),
        matches('Tests finished in\\s+\\d+ ms\n.*'),
      ]),
    );
  });
}
