import 'dart:io';

import 'package:dartle/dartle.dart';
import 'package:dartle/dartlex.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _buildDirectory = 'test/test_builds/task_deps_across_phases';
const allUpToDate = 'Everything is up-to-date!';

Future<void> _cleanupProject() async {
  await deleteAll(
    entities([], [
      dirEntry(p.join(_buildDirectory, '.dartle_tool'), includeHidden: true),
      dirEntry(p.join(_buildDirectory, '.dart_tool'), includeHidden: true),
      dirEntry(p.join(_buildDirectory, 'target')),
    ]),
  );
}

Stream<String> _targetDirFiles() async* {
  final target = Directory(p.join(_buildDirectory, 'target'));
  await for (final child in target.list()) {
    yield p.relative(child.path, from: target.path);
  }
}

Future<void> _assertCountBytesOutput() async {
  final bytesContents = await File(
    p.join(_buildDirectory, 'target', 'bytes.txt'),
  ).readAsString();
  // on Windows, it seems to include the `\r` byte from the newline sequence
  expect(bytesContents, equals(Platform.isWindows ? '15' : '14'));
}

void main() {
  group('Task deps across phases', () {
    File buildExe = File('');

    setUpAll(() async {
      buildExe = await createDartExe(
        File(p.join(_buildDirectory, 'dartle.dart')),
      );
    });

    tearDownAll(() async {
      await deleteAll(file(buildExe.path));
      await _cleanupProject();
    });

    setUp(() async {
      await _cleanupProject();
    });

    Future<ExecReadResult> runDartBuild(List<String> args) async {
      return execRead(
        runDartExe(buildExe, args: args, workingDirectory: _buildDirectory),
        name: 'io_checks test dart build',
      );
    }

    test('can run simple task and produce expected outputs', () async {
      var proc = await runDartBuild(const ['--no-color']);
      expect(proc.exitCode, equals(0));
      expect(
        proc.stdout[0],
        endsWith(
          'Executing 2 tasks out of a total of 4 tasks:'
          ' 1 task (default), 1 requirement',
        ),
      );
      expect(proc.stderr, isEmpty);
      expect(await _targetDirFiles().toList(), equals(['output.txt']));
    });

    test('can run task that depends on previous phase task', () async {
      var proc = await runDartBuild(const ['count']);
      expect(proc.exitCode, equals(0));
      final outputFiles = await _targetDirFiles().toList();
      expect(outputFiles, hasLength(2));
      expect(outputFiles, containsAll(['output.txt', 'bytes.txt']));
      await _assertCountBytesOutput();
    });

    test(
      'can run clean task and then re-compute inputs of other tasks and run them',
      () async {
        var proc = await runDartBuild(const ['count']);
        expect(proc.exitCode, equals(0));
        final outputFiles = await _targetDirFiles().toList();
        expect(outputFiles, hasLength(2));
        expect(outputFiles, containsAll(['output.txt', 'bytes.txt']));
        await _assertCountBytesOutput();

        var proc2 = await runDartBuild(const ['clean', 'count']);
        expect(proc2.exitCode, equals(0));
        final outputFiles2 = await _targetDirFiles().toList();
        expect(outputFiles2, hasLength(2));
        expect(outputFiles2, containsAll(['output.txt', 'bytes.txt']));
        await _assertCountBytesOutput();
      },
    );

    test(
      'requirement task is not executed if main task is up-to-date',
      () async {
        // execute the default task so it becomes up-to-date
        var proc = await runDartBuild(const ['--no-color', 'createOutput']);
        expect(proc.exitCode, equals(0));
        expect(
          proc.stdout,
          containsAll([
            endsWith(
              'Executing 2 tasks out of a total of 4 tasks:'
              ' 1 task selected, 1 requirement',
            ),
            endsWith("Running task 'prepareSomething'"),
            endsWith("Running task 'createOutput'"),
          ]),
        );

        // now, trying to execute it again means the task is up-to-date
        // so the task doesn't run, and hence its requirement doesn't run.
        proc = await runDartBuild(const ['--no-color', 'createOutput']);
        expect(proc.exitCode, equals(0));
        expect(proc.stdout[0], endsWith(allUpToDate));
      },
    );
  });
}
