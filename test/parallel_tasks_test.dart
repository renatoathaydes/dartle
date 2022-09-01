import 'dart:io';

import 'package:dartle/dartle.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

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

  Future<ProcessResult> runBuild(List<String> args) async {
    return startProcess(
        runDartExe(parallelTasksBuild,
            args: args, workingDirectory: 'test/test_builds/many_tasks'),
        'many_tasks test dart build');
  }

  group('Parallel Tasks', () {
    test('can run with -p flag', () async {
      var proc = await runBuild(
          const ['-p', '--no-color', 'sayHi', 'sayHo', 'sayArgs']);
      expect(
          proc.stdout[0],
          contains('Executing 3 tasks out of a total of 4 tasks:'
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
          contains('Executing 4 tasks out of a total of 4 tasks:'
              ' 1 task selected, 3 dependencies'));
      var tasksOutput = proc.stdout.skip(1).join();
      expect(tasksOutput, contains('Env={}'));
    });

    test('run in the same Isolate with the --no-parallel flag', () async {
      // without the -p flag, all tasks run in the main Isolate
      var proc = await runBuild(
          const ['showEnv', '--no-parallel-tasks', '--no-color']);

      expect(
          proc.stdout[0],
          contains('Executing 4 tasks out of a total of 4 tasks:'
              ' 1 task selected, 3 dependencies'));
      var tasksOutput = proc.stdout.skip(1).join();
      final pattern = RegExp('Env={(.*)}');
      final match = pattern.firstMatch(tasksOutput);
      expect(match, isNotNull);
      final envValues = match?.group(1)?.split(', ') ?? [];
      expect(envValues, containsAll({'hi', 'args', 'ho'}));
      expect(envValues, hasLength(3));
    });
  });
}
