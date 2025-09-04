import 'dart:async';

import 'package:dartle/src/_log.dart';
import 'package:dartle/src/ansi_message.dart';
import 'package:dartle/src/message.dart';
import 'package:io/ansi.dart' as ansi;
import 'package:logging/logging.dart' as log;
import 'package:test/test.dart';

void main() {
  group('simple log', () {
    tearDownAll(() async => await deactivateLogging());

    setUp(() async => await deactivateLogging());

    test('only logs message at enabled levels', () {
      activateLogging(log.Level.WARNING, colorfulLog: false);
      final logged = capturingLogs(() {
        logger.log(log.Level.FINE, 'fine');
        logger.log(log.Level.INFO, 'info');
        logger.log(log.Level.WARNING, 'warning');
        logger.log(log.Level.SEVERE, 'severe');
      });

      expect(
        logged,
        emitsInOrder([endsWith('WARN - warning'), endsWith('ERROR - severe')]),
      );
    });

    test('can log a message with color', () {
      activateLogging(
        log.Level.WARNING,
        colorfulLog: true,
        logName: 'test-log',
      );
      final logged = capturingLogs(
        () => logger.log(log.Level.WARNING, 'hello with color'),
      );
      expect(
        logged,
        emits(
          allOf(
            startsWith(ansi.yellow.escape),
            endsWith('WARN - hello with color${ansi.resetAll.escape}'),
          ),
        ),
      );
    });

    test('can log a message without color', () {
      activateLogging(
        log.Level.WARNING,
        colorfulLog: false,
        logName: 'test-log',
      );
      final logged = capturingLogs(
        () => logger.log(log.Level.WARNING, 'hello with color'),
      );
      expect(
        logged,
        emits(
          allOf(
            isNot(startsWith(ansi.yellow.escape)),
            endsWith('WARN - hello with color'),
          ),
        ),
      );
    });

    test('can log plain text message even when color is enabled', () {
      activateLogging(
        log.Level.WARNING,
        colorfulLog: true,
        logName: 'test-log',
      );
      final logged = capturingLogs(
        () => logger.log(log.Level.WARNING, PlainMessage('plain text')),
      );
      expect(logged, emits(equals('plain text')));
    });
  }, timeout: const Timeout(Duration(seconds: 1)));

  group('ColoredMessage log', () {
    tearDownAll(() async => await deactivateLogging());

    setUp(() async => await deactivateLogging());

    test('can log a message with color', () {
      activateLogging(log.Level.INFO, colorfulLog: true, logName: 'test-log');
      final logged = capturingLogs(
        () =>
            logger.info(const ColoredLogMessage('blue message', LogColor.blue)),
      );
      expect(
        logged,
        emits(equals('${ansi.blue.escape}blue message${ansi.resetAll.escape}')),
      );
    });

    test('can log a message without color', () {
      activateLogging(log.Level.INFO, colorfulLog: false, logName: 'test-log');
      final logged = capturingLogs(
        () =>
            logger.info(const ColoredLogMessage('blue message', LogColor.blue)),
      );
      expect(logged, emits(equals('blue message')));
    });
  }, timeout: const Timeout(Duration(seconds: 1)));

  group('AnsiMessage log', () {
    tearDownAll(() async => await deactivateLogging());

    setUp(() async => await deactivateLogging());

    test('can log a message without color', () {
      activateLogging(log.Level.INFO, colorfulLog: false, logName: 'test-log');
      final logged = capturingLogs(
        () => logger.info(
          const AnsiMessage([
            AnsiMessagePart.code(ansi.green),
            AnsiMessagePart.text('Green Text'),
            AnsiMessagePart.code(ansi.blue),
            AnsiMessagePart.text('Blue!'),
          ]),
        ),
      );
      expect(logged, emits(equals('Green TextBlue!')));
    });

    test('can log a message with color', () {
      activateLogging(log.Level.INFO, colorfulLog: true, logName: 'test-log');
      final logged = capturingLogs(
        () => logger.info(
          const AnsiMessage([
            AnsiMessagePart.code(ansi.green),
            AnsiMessagePart.text('Green Text'),
            AnsiMessagePart.code(ansi.blue),
            AnsiMessagePart.text('Blue!'),
          ]),
        ),
      );
      expect(
        logged,
        emits(
          equals(
            '${ansi.green.escape}'
            'Green Text${ansi.blue.escape}'
            'Blue!${ansi.resetAll.escape}',
          ),
        ),
      );
    });

    test('can log a message with color (explicit reset)', () {
      activateLogging(log.Level.INFO, colorfulLog: true, logName: 'test-log');
      final logged = capturingLogs(
        () => logger.info(
          const AnsiMessage([
            AnsiMessagePart.code(ansi.green),
            AnsiMessagePart.text('Green Text'),
            AnsiMessagePart.code(ansi.resetAll),
          ]),
        ),
      );
      expect(
        logged,
        emits(
          equals(
            '${ansi.green.escape}'
            'Green Text${ansi.resetAll.escape}',
          ),
        ),
      );
    });
  }, timeout: const Timeout(Duration(seconds: 1)));
}

Stream<String> capturingLogs(void Function() action) {
  final captured = StreamController<String>();
  runZoned(
    action,
    zoneValues: {#_log_test: true},
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) =>
          captured.add(line),
    ),
  );
  return captured.stream;
}
