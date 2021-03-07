import 'dart:io';

@TestOn('!browser')
import 'package:dartle/dartle.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('Build information', () {
    // create a snapshot so we can run the build quickly, several times
    var manyTasksBuild = File('');

    setUpAll(() async {
      manyTasksBuild =
          (await createDartExe(File('test/test_builds/many_tasks/dartle.dart')))
              .absolute;
    });
    tearDownAll(() async {
      await deleteAll(FileCollection([manyTasksBuild]));
    });

    Future<ProcessResult> runExampleDartBuild(List<String> args) async {
      return startProcess(
          runDartExe(manyTasksBuild,
              args: args, workingDirectory: 'test/test_builds/many_tasks'),
          'many_tasks test dart build');
    }

    test('logs expected output', () async {
      var proc = await runExampleDartBuild(const []);
      expect(
          proc.stdout[0],
          contains('Executing 9 tasks out of a total of 15 tasks:'
              ' 3 tasks (default), 6 due to dependencies'));
      expect(proc.stdout[1], contains("Running task 'd'"));
      expect(proc.stdout[2], contains("Running task 'e'"));
      expect(proc.stdout[3], contains("Running task 'm'"));
      expect(proc.stdout[4], contains("Running task 'c'"));
      expect(proc.stdout[5], contains("Running task 'g'"));
      expect(proc.stdout[6], contains("Running task 'n'"));
      expect(proc.stdout[7], contains("Running task 'f'"));
      expect(proc.stdout[8], contains("Running task 'b'"));
      expect(proc.stdout[9], contains("Running task 'a'"));
      expect(proc.stdout[10], startsWith('✔ Build succeeded in '));
      // expect(proc.stdout[10], startsWith('\x1B[38;5;2m✔ Build succeeded in '));
      // expect(proc.stdout[10], endsWith(' ms\x1B[0m'));
      expect(proc.stdout.length, equals(11));
      expect(proc.exitCode, equals(0));
      expect(proc.stderr, isEmpty);

      proc = await runExampleDartBuild(['l']);
      expect(
          proc.stdout[0],
          contains('Executing 1 task out of a total of 15 tasks:'
              ' 1 task selected, 0 due to dependencies'));
      expect(proc.stdout[1], contains("Running task 'l'"));
      expect(proc.stdout[2], startsWith('✔ Build succeeded in '));
      // expect(proc.stdout[2], startsWith('\x1B[38;5;2m✔ Build succeeded in '));
      // expect(proc.stdout[2], endsWith(' ms\x1B[0m'));
      // expect(proc.stdout.length, equals(3));
      expect(proc.exitCode, equals(0));
      expect(proc.stderr, isEmpty);
    });

    test('logs expected output for single task, without colors', () async {
      var proc = await runExampleDartBuild(const ['--no-colorful-log', 'd']);
      expect(
          proc.stdout[0],
          contains('Executing 1 task out of a total of 15 tasks:'
              ' 1 task selected, 0 due to dependencies'));
      expect(proc.stdout[1], contains("Running task 'd'"));
      expect(proc.stdout[2], startsWith('✔ Build succeeded in '));
      expect(proc.stdout[2], endsWith(' ms'));
      expect(proc.stdout.length, equals(3));
      expect(proc.exitCode, equals(0));
      expect(proc.stderr, isEmpty);
    });

    test('can show all tasks', () async {
      var proc = await runExampleDartBuild(const ['-s']);

      final expectedOutput = r'''
======== Showing build information only, no tasks will be executed ========

Tasks declared in this build:

  * a [default]
      Task A
  * b [default]
      Task B
  * c [default]
  * d
  * e
  * f
  * g
  * h
  * i
  * j
  * k
  * l
  * m
  * n
  * o
      Task O

The following tasks were selected to run, in order:

  d ---> c ---> g ---> f ---> b ---> a
  e             n                     
  m                                   
''';

      expect(proc.stdout.join('\n'), equals(expectedOutput));
      expect(proc.exitCode, equals(0));
      expect(proc.stderr, isEmpty);
    });

    test('can show task graph', () async {
      var proc = await runExampleDartBuild(const ['-g']);

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

  d ---> c ---> g ---> f ---> b ---> a
  e             n                     
  m                                   
''';

      expect(proc.stdout.join('\n'), equals(expectedOutput));
      expect(proc.exitCode, equals(0));
      expect(proc.stderr, isEmpty);
    });
  });
}
