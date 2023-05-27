import 'dart:io';

import 'package:dartle/dartle.dart';
import 'package:dartle/dartlex.dart';
import 'package:test/test.dart';

void main() {
  // create a snapshot so we can run the build quickly, several times
  var parallelTasksBuild = File('');

  setUpAll(() async {
    parallelTasksBuild = (await createDartExe(
        File('test/test_builds/parallel_tasks/dartle.dart')));
  });
  tearDownAll(() async {
    await deleteAll(files([parallelTasksBuild.path]));
  });

  Future<ExecReadResult> runBuild(List<String> args,
      {Set<int> successExitCodes = const {0}}) async {
    return execRead(
        runDartExe(parallelTasksBuild,
            args: args, workingDirectory: 'test/test_builds/parallel_tasks'),
        name: 'parallel_tasks test dart build',
        isCodeSuccessful: (i) => successExitCodes.contains(i));
  }

  group('Parallel Tasks', () {
    test('can run with -p flag', () async {
      var proc = await runBuild(
          const ['-p', '--no-color', 'sayHi', 'sayHo', 'sayArgs']);
      expect(
          proc.stdout[0],
          contains('Executing 3 tasks out of a total of 6 tasks:'
              ' 3 tasks selected'));
      final tasksOutput = proc.stdout.skip(1).join('\n');
      expect(tasksOutput, contains("Running task 'sayHi'"));
      expect(tasksOutput, contains("Running task 'sayHo'"));
      expect(tasksOutput, contains("Running task 'sayArgs'"));
    });

    test('run in separate Isolates with -p flag', () async {
      // the showEnv task depends on the others, so will run in the main Isolate,
      // hence it should not see the env modifications the other tasks made
      // because with the -p flag, they should run in different Isolates.
      var proc = await runBuild(const ['-p', 'showEnv', '--no-color']);

      expect(
          proc.stdout[0],
          contains('Executing 4 tasks out of a total of 6 tasks:'
              ' 1 task selected, 3 dependencies'));
      var tasksOutput = proc.stdout.skip(1).join();
      expect(tasksOutput, contains('Env={}'));
    });

    test('loggers in separate Isolates with -p flag', () async {
      // the showEnv task depends on the others, so will run in the main Isolate,
      // hence it should not see the env modifications the other tasks made
      // because with the -p flag, they should run in different Isolates.
      var proc = await runBuild(const ['-p', 'sayHi', 'sayHo', '--no-color']);

      expect(
          proc.stdout[0],
          contains('Executing 2 tasks out of a total of 6 tasks:'
              ' 2 tasks selected'));
      var tasksOutput = proc.stdout.skip(1).join();
      expect(
          tasksOutput,
          allOf(
            contains(RegExp(r'dartle\[dartle-Actor-\d \d+] - INFO - Hi')),
            contains(RegExp(r'dartle\[dartle-Actor-\d \d+] - INFO - Ho')),
          ));
    });

    test('run in the same Isolate with the --no-parallel flag', () async {
      // without the -p flag, all tasks run in the main Isolate
      var proc = await runBuild(
          const ['showEnv', '--no-parallel-tasks', '--no-color']);

      expect(
          proc.stdout[0],
          contains('Executing 4 tasks out of a total of 6 tasks:'
              ' 1 task selected, 3 dependencies'));
      var tasksOutput = proc.stdout.skip(1).join();
      final pattern = RegExp('Env={(.*)}');
      final match = pattern.firstMatch(tasksOutput);
      expect(match, isNotNull);
      final envValues = match?.group(1)?.split(', ') ?? [];
      expect(envValues, containsAll({'hi', 'args', 'ho'}));
      expect(envValues, hasLength(3));
    });

    test('stackTraces are logged if log level is debug', () async {
      var proc = await runBuild(
          const ['throw', 'delayedMessage', '-l', 'debug', '--no-color'],
          successExitCodes: const {2});

      var tasksOutput = proc.stdout.join();
      expect(
          tasksOutput,
          contains(RegExp(r'ERROR - Several errors have occurred',
              multiLine: true)));
      expect(tasksOutput,
          contains(RegExp(r'ERROR - Multiple stackTraces', multiLine: true)));
      expect(tasksOutput,
          contains(RegExp(r'\s*#[0|1]\s+_File.open.', multiLine: true)));
      expect(tasksOutput,
          contains(RegExp(r'\s*#\d\s+_readNonExistingFile', multiLine: true)));
      expect(tasksOutput,
          contains(RegExp(r'\s*#\d\s+throwError', multiLine: true)));
      expect(tasksOutput,
          contains(RegExp(r'\s*#0\s+actorAction', multiLine: true)));
      expect(
          tasksOutput,
          contains(
              RegExp(r"Task 'delayedMessage' was cancelled", multiLine: true)));
    });
  });
}
