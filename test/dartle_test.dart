import 'dart:io';

@TestOn('!browser')
import 'package:dartle/dartle.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

helloTask([_]) => null;

void main() {
  group('Task name', () {
    test('can be inferred from function', () {
      expect(Task(helloTask).name, equals('helloTask'));
    });
    test('can be defined explicitly', () {
      expect(Task(helloTask, name: 'foo').name, equals('foo'));
    });
    test('cannot be inferred from lambda', () {
      expect(() => Task(([_]) {}).name, throwsArgumentError);
    });
  });
  group('Task execution', () {
    final outputFile = File('example/output.txt');

    // create a snapshot so we can run the build quickly, several times
    File exampleDartleBuild;

    setUpAll(() async {
      exampleDartleBuild =
          (await createDartSnapshot(File('example/dartle.dart'))).absolute;
    });
    tearDownAll(() async {
      await deleteAll(FileCollection([outputFile, exampleDartleBuild]));
    });

    Future<ProcessResult> runExampleDartBuild(List<String> args) async {
      return startProcess(
          runDartSnapshot(exampleDartleBuild,
              args: args, workingDirectory: 'example'),
          'example dart build');
    }

    test('logs expected output', () async {
      var proc = await runExampleDartBuild(['hello']);
      expect(
          proc.stdout[0],
          contains('Executing 1 task out of a total of 4 tasks:'
              ' 1 task selected, 0 due to dependencies'));
      expect(proc.stdout[1], contains("Running task 'hello'"));
      expect(proc.stdout[2], equals('Hello World!'));
      expect(proc.stdout[3], contains("Build succeeded"));
      expect(proc.stdout.length, equals(4));
      expect(proc.exitCode, equals(0));
      expect(proc.stderr, isEmpty);

      // run with one argument now
      proc = await runExampleDartBuild(['hello', ':Elvis']);
      expect(
          proc.stdout[0],
          contains('Executing 1 task out of a total of 4 tasks:'
              ' 1 task selected, 0 due to dependencies'));
      expect(proc.stdout[1], contains("Running task 'hello'"));
      expect(proc.stdout[2], equals('Hello Elvis!'));
      expect(proc.stdout[3], contains("Build succeeded"));
      expect(proc.stdout.length, equals(4));
      expect(proc.exitCode, equals(0));
      expect(proc.stderr, isEmpty);

      proc = await runExampleDartBuild(['bye']);
      expect(
          proc.stdout[0],
          contains('Executing 1 task out of a total of 4 tasks:'
              ' 1 task selected, 0 due to dependencies'));
      expect(proc.stdout[1], contains("Running task 'bye'"));
      expect(proc.stdout[2], equals('Bye!'));
      expect(proc.stdout[3], contains("Build succeeded"));
      expect(proc.stdout.length, equals(4));
      expect(proc.exitCode, equals(0));
      expect(proc.stderr, isEmpty);
    });

    test('runs only tasks that are required, unless forced', () async {
      // delete task output to make sure task runs
      await ignoreExceptions(() async => await outputFile.delete());

      var proc = await runExampleDartBuild(['encode']);
      expect(
          proc.stdout[0],
          contains('Executing 1 task out of a total of 4 tasks:'
              ' 1 task selected, 0 due to dependencies'));
      expect(proc.stdout[1], contains("Running task 'encodeBase64'"));
      expect(proc.stdout[2], contains("Build succeeded"));
      expect(proc.stdout.length, equals(3));
      expect(proc.exitCode, equals(0));
      expect(proc.stderr, isEmpty);

      // verify that the task really ran
      expect(await outputFile.exists(), isTrue);
      expect(await outputFile.readAsString(), equals("SGVsbG8gRGFydGxlIQ=="));

      // now the output exists, it should not run again
      proc = await runExampleDartBuild(['encode']);
      expect(
          proc.stdout[0],
          contains('Executing 0 tasks out of a total of 4 tasks:'
              ' 1 task selected, 0 due to dependencies'));
      expect(proc.stdout[1], contains("Build succeeded"));
      expect(proc.stdout.length, equals(2));
      expect(proc.exitCode, equals(0));
      expect(proc.stderr, isEmpty);

      // when we force the task to run, it must run again
      proc = await runExampleDartBuild(['encode', '-f']);
      expect(
          proc.stdout[0],
          contains('Executing 1 task out of a total of 4 tasks:'
              ' 1 task selected, 0 due to dependencies'));
      expect(proc.stdout[1], contains("Running task 'encodeBase64'"));
      expect(proc.stdout[2], contains("Build succeeded"));
      expect(proc.stdout.length, equals(3));
      expect(proc.exitCode, equals(0));
      expect(proc.stderr, isEmpty);
    });

    test('errors if task does not exist', () async {
      // delete task output to make sure task runs
      await ignoreExceptions(() async => await outputFile.delete());

      var proc = await runExampleDartBuild(['foo']);
      expect(proc.stdout.length, equals(2));
      expect(proc.stdout[0],
          contains("ERROR - Invocation problem: Task 'foo' does not exist"));
      expect(proc.stdout[1], contains('Build failed'));
      expect(proc.exitCode, equals(1));
    });

    test('errors if option does not exist', () async {
      // delete task output to make sure task runs
      await ignoreExceptions(() async => await outputFile.delete());

      var proc = await runExampleDartBuild(['--foo']);
      expect(proc.stdout.length, equals(2));
      expect(
          proc.stdout[0],
          contains('Could not find an option named "foo"...'
              ' run with the -h flag to see usage.'));
      expect(proc.stdout[1], contains('Build failed'));
      expect(proc.exitCode, equals(4));
    });
  });
}
