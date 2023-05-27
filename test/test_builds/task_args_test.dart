import 'dart:io';

import 'package:dartle/dartle.dart';
import 'package:dartle/dartlex.dart';
import 'package:path/path.dart' as path;
import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';

const _buildDirectory = 'test/test_builds/task_args';

Future<void> _deleteDartleToolDir() async {
  await deleteAll(
      dir(path.join(_buildDirectory, '.dartle_tool'), includeHidden: true));
}

void main() {
  File buildExe = File('');

  setUpAll(() async {
    buildExe =
        await createDartExe(File(path.join(_buildDirectory, 'dartle.dart')));
  });

  tearDownAll(() async {
    await deleteAll(file(buildExe.path));
  });

  tearDown(() async {
    await _deleteDartleToolDir();
  });

  Future<ExecReadResult> runExampleDartBuild(List<String> args,
      {bool Function(int) isCodeSuccessful = noCheck}) async {
    return execRead(
        runDartExe(buildExe,
            args: ['--no-color', ...args], workingDirectory: _buildDirectory),
        name: 'io_checks test dart build',
        isCodeSuccessful: isCodeSuccessful);
  }

  group('noArgs', () {
    test('task runs successfully without arguments', () async {
      final result = await runExampleDartBuild(const ['noArgs']);
      expect(result.exitCode, equals(0));
      expect(result.stdout, hasLength(4));
      expect(result.stdout[1], endsWith("INFO - Running task 'noArgs'"));
      expect(result.stdout[2], equals("ok"));
      expect(result.stdout[3], contains('Build succeeded'));
      expect(result.stderr, isEmpty);
    });

    test('task arguments are not accepted by default', () async {
      final result = await runExampleDartBuild(const ['noArgs', ':a']);
      expect(result.exitCode, equals(1));
      expect(result.stdout, hasLength(2));
      expect(
          result.stdout[0],
          endsWith('ERROR - Invocation problem: '
              "Invalid arguments for task 'noArgs': [a] - "
              "no arguments are expected"));
      expect(result.stdout[1], contains('Build failed'));
      expect(result.stderr, isEmpty);
    });
  });

  group('requiresArgs', () {
    test('task runs successfully with one arg', () async {
      final result =
          await runExampleDartBuild(const ['requiresArgs', ':hello', ':foo']);
      expect(result.exitCode, equals(0));
      expect(result.stdout, hasLength(4));
      expect(result.stdout[1], endsWith("INFO - Running task 'requiresArgs'"));
      expect(result.stdout[2], equals("Args: hello foo"));
      expect(result.stdout[3], contains('Build succeeded'));
      expect(result.stderr, isEmpty);
    });

    test('task execution throws exception if no args are provided', () async {
      final result = await runExampleDartBuild(const ['requiresArgs']);
      expect(result.exitCode, equals(2));
      expect(result.stdout, hasLength(4));
      expect(result.stdout[0], contains('INFO - Executing 1 task'));
      expect(result.stdout[1], endsWith("INFO - Running task 'requiresArgs'"));
      expect(
          result.stdout[2],
          endsWith(
              "ERROR - Task 'requiresArgs' failed: Exception: Args is empty"));
      expect(result.stdout[3], contains('Build failed'));
      expect(result.stderr, isEmpty);
    });
  });

  group('validatedArgs', () {
    test('validator accepts valid arguments', () async {
      final result =
          await runExampleDartBuild(const ['numberArgs', ':1', ':2']);
      expect(result.exitCode, equals(0));
      expect(result.stdout, hasLength(4));
      expect(result.stdout[1], endsWith("INFO - Running task 'numberArgs'"));
      expect(result.stdout[2], equals("Args Sum: 3"));
      expect(result.stdout[3], contains('Build succeeded'));
      expect(result.stderr, isEmpty);
    });
  });

  test('multiple task validation failures are reported properly', () async {
    final result = await runExampleDartBuild(
        const ['noArgs', ':bar', 'numberArgs', ':foo']);
    expect(result.exitCode, equals(1));
    expect(result.stdout, hasLength(4));
    expect(result.stdout[0],
        endsWith("ERROR - Several invocation problems found:"));
    expect(
        result.stdout[1],
        equals(
            "  * Invalid arguments for task 'noArgs': [bar] - no arguments are expected"));
    expect(
        result.stdout[2],
        equals(
            "  * Invalid arguments for task 'numberArgs': [foo] - only number arguments allowed"));
    expect(result.stdout[3], contains('Build failed'));
    expect(result.stderr, isEmpty);
  });

  test('multiple tasks executed with valid arguments', () async {
    final result = await runExampleDartBuild(const [
      '--no-parallel-tasks',
      'numberArgs',
      ':1',
      'requiresArgs',
      ':hello',
      ':bye',
    ]);
    expect(result.exitCode, equals(0));
    expect(result.stdout, hasLength(6));
    expect(result.stdout[1], endsWith("INFO - Running task 'numberArgs'"));
    expect(result.stdout[2], equals("Args Sum: 1"));
    expect(result.stdout[3], endsWith("INFO - Running task 'requiresArgs'"));
    expect(result.stdout[4], equals("Args: hello bye"));
    expect(result.stdout[5], contains('Build succeeded'));
    expect(result.stderr, isEmpty);
  });
}

bool noCheck(int i) => true;
