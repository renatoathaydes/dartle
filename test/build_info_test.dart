import 'dart:io';

import 'package:dartle/dartle.dart';
import 'package:dartle/dartlex.dart';
import 'package:test/test.dart';

void main() {
  group('Build information', () {
    // create a snapshot so we can run the build quickly, several times
    var manyTasksBuild = File('');

    setUpAll(() async {
      manyTasksBuild =
          await createDartExe(File('test/test_builds/many_tasks/dartle.dart'));
    });
    tearDownAll(() async {
      await deleteAll(file(manyTasksBuild.path));
    });

    Future<ExecReadResult> runExampleDartBuild(List<String> args,
        {bool noColorEnv = false}) async {
      return execRead(
          runDartExe(manyTasksBuild,
              environment: noColorEnv ? const {'NO_COLOR': '1'} : null,
              args: args,
              workingDirectory: 'test/test_builds/many_tasks'),
          name: 'many_tasks test dart build');
    }

    test('logs expected output', () async {
      var proc = await runExampleDartBuild(const []);
      expect(
          proc.stdout[0],
          contains(
              'Executing \x1B[1m9 tasks\x1B[22m out of a total of 15 tasks:'
              ' 3 tasks (\x1B[90mdefault\x1B[0m), 6 dependencies'));
      expect(proc.stdout[1], contains("Running task 'd'"));
      expect(proc.stdout[2], contains("Running task 'e'"));
      expect(proc.stdout[3], contains("Running task 'm'"));
      expect(proc.stdout[4], contains("Running task 'c'"));
      expect(proc.stdout[5], contains("Running task 'g'"));
      expect(proc.stdout[6], contains("Running task 'n'"));
      expect(proc.stdout[7], contains("Running task 'f'"));
      expect(proc.stdout[8], contains("Running task 'b'"));
      expect(proc.stdout[9], contains("Running task 'a'"));
      expect(proc.stdout[10], startsWith('\x1B[32m✔ Build succeeded in '));
      expect(proc.stdout.length, equals(11));
      expect(proc.exitCode, equals(0));
      expect(proc.stderr, isEmpty);

      proc = await runExampleDartBuild(['l']);
      expect(
          proc.stdout[0],
          contains('Executing \x1B[1m1 task\x1B[22m out of a total of 15 tasks:'
              ' 1 task selected'));
      expect(proc.stdout[1], contains("Running task 'l'"));
      expect(proc.stdout[2], startsWith('\x1B[32m✔ Build succeeded in '));
      expect(proc.exitCode, equals(0));
      expect(proc.stderr, isEmpty);
    });

    test('logs expected output for single task, without colors', () async {
      var proc = await runExampleDartBuild(const ['--no-color', 'd']);
      expect(
          proc.stdout[0],
          contains('Executing 1 task out of a total of 15 tasks:'
              ' 1 task selected'));
      expect(proc.stdout[1], contains("Running task 'd'"));
      expect(proc.stdout[2], startsWith('✔ Build succeeded in '));
      expect(proc.stdout[2], endsWith(' ms'));
      expect(proc.stdout.length, equals(3));
      expect(proc.exitCode, equals(0));
      expect(proc.stderr, isEmpty);
    });

    test('can show all tasks', () async {
      var proc =
          await runExampleDartBuild(const ['-s', '--no-color', '-l', 'debug']);

      final expectedOutput = r'''
======== Showing build information only, no tasks will be executed ========

Tasks declared in this build:

==> Setup Phase:
  No tasks in this phase.
==> Build Phase:
  * a [default] [always-runs]
      Task A
  * b [default] [always-runs]
      Task B
  * c [default] [always-runs]
  * d [always-runs]
  * e [always-runs]
  * f [always-runs]
  * g [always-runs]
  * i
  * j
  * k
  * l
      taskArguments: all arguments are accepted
  * m [up-to-date]
      runCondition: RunAtMostEvery{0:00:04.000000}
  * n [always-runs]
  * o
      Task O
==> TearDown Phase:
  * h

The following tasks were selected to run, in order:

  d
  e
  m
      c
          g
          n
              f
                  b
                      a
''';

      const infoLine =
          '======== Showing build information only, no tasks will be executed ========';

      expect(proc.stdout, contains(infoLine));

      // remove all logs before the relevant line
      final infoLineIndex = proc.stdout.indexOf(infoLine);
      expect(
          proc.stdout.skip(infoLineIndex).join('\n'), equals(expectedOutput));
      expect(proc.exitCode, equals(0));
      expect(proc.stderr, isEmpty);
    });

    test('can show task graph', () async {
      var proc = await runExampleDartBuild(const ['-g', '--no-color']);

      final expectedOutput = r'''
======== Showing build information only, no tasks will be executed ========

Tasks Graph:

- a
  +--- b
  |     \--- f
  |          +--- g
  |          |     \--- c
  |          |          +--- d
  |          |          |--- e
  |          |          \--- m
  |          \--- n
  \--- c ...
- h
- i
  \--- d
- j
- k
  \--- a ...
- l
- o

The following tasks were selected to run, in order:

  d
  e
  m
      c
          g
          n
              f
                  b
                      a
''';

      expect(proc.stdout.join('\n'), equals(expectedOutput));
      expect(proc.exitCode, equals(0));
      expect(proc.stderr, isEmpty);
    });
  });
}
