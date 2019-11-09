import 'dart:io';

@TestOn('!browser')
import 'package:dartle/dartle.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('Build information', () {
    // create a snapshot so we can run the build quickly, several times
    File manyTasksBuild;

    setUpAll(() async {
      manyTasksBuild = (await createDartSnapshot(
              File('test/test_builds/many_tasks/dartle.dart')))
          .absolute;
    });
    tearDownAll(() async {
      await deleteAll(FileCollection([manyTasksBuild]));
    });

    Future<ProcessResult> runExampleDartBuild(List<String> args) async {
      return startProcess(
          runDartSnapshot(manyTasksBuild,
              args: args, workingDirectory: 'test/test_builds/many_tasks'),
          'many_tasks test dart build');
    }

    test('logs expected output', () async {
      var proc = await runExampleDartBuild(const []);
      expect(proc.stdout[0],
          contains('Executing 9 task(s) out of 3 selected task(s)'));
      expect(proc.stdout[1], contains("Running task 'd'"));
      expect(proc.stdout[2], contains("Running task 'e'"));
      expect(proc.stdout[3], contains("Running task 'm'"));
      expect(proc.stdout[4], contains("Running task 'c'"));
      expect(proc.stdout[5], contains("Running task 'g'"));
      expect(proc.stdout[6], contains("Running task 'n'"));
      expect(proc.stdout[7], contains("Running task 'f'"));
      expect(proc.stdout[8], contains("Running task 'b'"));
      expect(proc.stdout[9], contains("Running task 'a'"));
      expect(proc.stdout[10], contains("Build succeeded"));
      expect(proc.stdout.length, equals(11));
      expect(proc.exitCode, equals(0));
      expect(proc.stderr, isEmpty);

      proc = await runExampleDartBuild(['l']);
      expect(proc.stdout[0],
          contains('Executing 1 task(s) out of 1 selected task(s)'));
      expect(proc.stdout[1], contains("Running task 'l'"));
      expect(proc.stdout[2], contains("Build succeeded"));
      expect(proc.stdout.length, equals(3));
      expect(proc.exitCode, equals(0));
      expect(proc.stderr, isEmpty);
    });

    test('can show all tasks', () async {
      var proc = await runExampleDartBuild(const ['-s']);

      final expectedOutput = r"""
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

  d -> e -> m -> c -> g -> n -> f -> b -> a
""";

      expect(proc.stdout.join('\n'), equals(expectedOutput));
      expect(proc.exitCode, equals(0));
      expect(proc.stderr, isEmpty);
    });

    test('can show task graph', () async {
      var proc = await runExampleDartBuild(const ['-g']);

      final expectedOutput = r"""
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

  d -> e -> m -> c -> g -> n -> f -> b -> a
""";

      expect(proc.stdout.join('\n'), equals(expectedOutput));
      expect(proc.exitCode, equals(0));
      expect(proc.stderr, isEmpty);
    });
  });
}
