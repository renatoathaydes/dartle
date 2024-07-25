@TestOn('!browser')
library;

import 'dart:async';
import 'dart:io';

import 'package:dartle/dartle.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const logDateRegex = '\\d{4}-\\d{2}-\\d{2} \\d{2}.\\d{2}.\\d{2}\\.\\d+';
const infoLogPrefixRegex = '$logDateRegex - dartle\\[main \\d+\\] - INFO -';

void main() {
  group('dartlex', () {
    test('can execute simple build', () async {
      final projectDir = await _createTestProject('compiles_itself', '''
            import 'package:dartle/dartle.dart';
      
            final allTasks = [Task(hello)];
            main(List<String> args) async => run(args, tasks: allTasks.toSet());
            Future<void> hello(_) async => print('hello');
      ''');

      final result = await _runDartle(
          const ['hello', '--no-color', '--no-run-pub-get'], projectDir);

      expect(result.exitCode, equals(0), reason: result.toString());
      expect(result.stdout, hasLength(equals(6)));
      expect(result.stdout[0],
          matches('$infoLogPrefixRegex Detected changes in dartle.dart.*'));
      expect(result.stdout[1],
          matches('$infoLogPrefixRegex Re-compiled dartle.dart in .*'));
      expect(
          result.stdout[2],
          matches(
              '$infoLogPrefixRegex Executing 1 task out of a total of 1 task.*'));
      expect(
          result.stdout[3],
          matches(
              '$logDateRegex - dartle\\[main \\d+\\] - INFO - Running task \'hello\''));
      expect(result.stdout[4], matches('hello'));
      expect(result.stdout[5], matches('✔ Build succeeded in .*'));
      expect(result.stderr, equals([]));
    });

    test('can re-compile itself after changes', () async {
      String helloDartle(String helloTask) => '''
      import 'package:dartle/dartle.dart';
      
      final allTasks = [Task(hello)];
      main(List<String> args) async => run(args, tasks: allTasks.toSet());
      Future<void> hello(_) async => $helloTask
      ''';

      final projectDir = await _createTestProject(
          'mini_project', helloDartle('print("hello");'));

      final result =
          await _runDartle(const ['hello', '--no-run-pub-get'], projectDir);

      expect(result.exitCode, equals(0), reason: result.toString());
      expect(result.stdout, hasLength(equals(6)));
      expect(result.stdout[4], equals('hello'));
      expect(result.stderr, equals([]));

      // some OS's like to keep file change time resolution in the seconds
      await Future.delayed(Duration(seconds: 1));

      await File(p.join(projectDir.path, 'dartle.dart')).writeAsString(
          helloDartle('print("bye");'),
          mode: FileMode.writeOnly,
          flush: true);

      final result2 =
          await _runDartle(const ['hello', '--no-run-pub-get'], projectDir);

      expect(result2.exitCode, equals(0), reason: result2.stdout.toString());
      expect(result2.stdout, hasLength(equals(6)));
      expect(result2.stdout[4], equals('bye'));
      expect(result2.stderr, equals([]));

      // make sure it doesn't re-compile if there's no changes...

      // some OS's like to keep file change time resolution in the seconds
      await Future.delayed(Duration(seconds: 1));

      final result3 = await _runDartle(
          const ['hello', '--no-run-pub-get', '--no-color'], projectDir);

      expect(result3.exitCode, equals(0), reason: result3.stdout.toString());
      expect(result3.stdout, hasLength(equals(4)));
      expect(
          result3.stdout[0],
          matches(
              '$infoLogPrefixRegex Executing 1 task out of a total of 1 task.*'));
      expect(
          result3.stdout[1],
          matches(
              '$logDateRegex - dartle\\[main \\d+\\] - INFO - Running task \'hello\''));
      expect(result3.stdout[2], matches('bye'));
      expect(result3.stdout[3], matches('✔ Build succeeded in .*'));
      expect(result3.stderr, equals([]));
    });
  }, timeout: Timeout(const Duration(minutes: 1)));
}

Future<Directory> _createTestProject(
    String testProject, String dartleScript) async {
  final dir = Directory(p.join('test', 'test_builds', testProject));
  await dir.create();
  addTearDown(() async {
    await _waitForOrTimeout(() async {
      try {
        await dir.delete(recursive: true);
        return true;
      } on FileSystemException {
        // ignore
      }
      return false;
    }, 'Unable to delete test directory ${dir.absolute.path}');
  });
  final dartleFile = File(p.join(dir.path, 'dartle.dart'));
  await dartleFile.writeAsString(dartleScript, flush: true);
  return dir;
}

Future<ExecReadResult> _runDartle(List<String> args, Directory wrkDir) async {
  final dartle = File('bin/dartle.dart').absolute.path;
  return execRead(
      Process.start('dart', [dartle, ...args], workingDirectory: wrkDir.path),
      name: 'dartle');
}

Future<void> _waitForOrTimeout(Future<bool> Function() action, String error,
    {int tries = 10, Duration period = const Duration(seconds: 1)}) async {
  while (tries > 0) {
    if (await action()) return;
    tries--;
    await Future.delayed(period);
  }
  throw Exception(error);
}
