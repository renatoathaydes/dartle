import 'dart:io';

@TestOn('!browser')
import 'package:dartle/dartle.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../test_utils.dart';
import 'io_checks/dartle.dart';

const _buildDirectory = 'test/test_builds/io_checks';

const oneTaskExecutingMessage = 'Executing 1 task out of a total of 1 task:'
    ' 1 task selected';

const noTasksExecutingMessage = 'Executing 0 tasks out of a total of 1 task:'
    ' 1 task selected, 1 up-to-date';

Future<void> _deleteDartleToolDir() async {
  await deleteAll(
      dir(path.join(_buildDirectory, '.dartle_tool'), includeHidden: true));
}

void main() {
  group('IO Checks', () {
    final outputsDir = Directory(path.join(_buildDirectory, 'outputs'));
    Map<String, String?> outputFilesAtStart = {};

    setUp(() async {
      await _deleteDartleToolDir();
      final preExistingOutput = outputsDir.list(recursive: true);
      await for (final out in preExistingOutput) {
        outputFilesAtStart[out.path] =
            (out is File) ? await out.readAsString() : null;
      }
    });

    tearDown(() async {
      await _deleteDartleToolDir();
      await outputsDir.delete(recursive: true);
      await outputsDir.create();
      await _rebuildFileTree(outputFilesAtStart);
    });

    Future<ProcessResult> runExampleDartBuild(List<String> args) async {
      return startProcess(
          Process.start('dart', ['dartle.dart', ...args],
              workingDirectory: _buildDirectory),
          'io_checks test dart build');
    }

    test('can run simple task and produce expected outputs', () async {
      var proc =
          await runExampleDartBuild(const ['--no-colorful-log', 'base64']);
      expect(proc.exitCode, equals(0));
      expect(proc.stdout[0], contains(oneTaskExecutingMessage));
      expect(proc.stderr, isEmpty);
      await _expectFileTreeAfterBase64TaskRuns(
          outputsDir.path, outputFilesAtStart);
    });

    test('running second time skips the cached task', () async {
      var proc =
          await runExampleDartBuild(const ['--no-colorful-log', 'base64']);
      expect(proc.exitCode, equals(0));

      // run again
      proc = await runExampleDartBuild(const ['--no-colorful-log', 'base64']);
      expect(proc.exitCode, equals(0));

      expect(proc.stdout[0], contains(noTasksExecutingMessage));
      expect(proc.stderr, isEmpty);
      await _expectFileTreeAfterBase64TaskRuns(
          outputsDir.path, outputFilesAtStart);
    });

    test('running again time after change in inputs or outputs re-runs task',
        () async {
      final inputFile = File(path.join(
          _buildDirectory, inputs.directories.first.path, 'more', 'foo.txt'));
      final originalInputFileContents = await inputFile.readAsString();

      var proc =
          await runExampleDartBuild(const ['--no-colorful-log', 'base64']);
      expect(proc.exitCode, equals(0));

      // change an input file
      await inputFile.writeAsString('not foo', flush: true);

      Future<void> revertInputFileChange() =>
          inputFile.writeAsString(originalInputFileContents, flush: true);

      // revert the change later even if test fails
      addTearDown(revertInputFileChange);

      // run again
      proc = await runExampleDartBuild(const ['--no-colorful-log', 'base64']);
      expect(proc.exitCode, equals(0));
      expect(proc.stdout[0], contains(oneTaskExecutingMessage));
      expect(proc.stderr, isEmpty);

      // change an output file
      await File(path.join(outputsDir.path, 'hello.b64.txt'))
          .writeAsString('changed this', flush: true);

      // run again
      proc = await runExampleDartBuild(const ['--no-colorful-log', 'base64']);
      expect(proc.exitCode, equals(0));
      expect(proc.stdout[0], contains(oneTaskExecutingMessage));
      expect(proc.stderr, isEmpty);

      // reset input so the output should go back to the expected state
      await revertInputFileChange();

      // run again
      proc = await runExampleDartBuild(const ['--no-colorful-log', 'base64']);
      expect(proc.exitCode, equals(0));

      // finally, the outputs should be as expected after running the task again
      await _expectFileTreeAfterBase64TaskRuns(
          outputsDir.path, outputFilesAtStart);
    });
  });
}

Future<void> _expectFileTreeAfterBase64TaskRuns(
    String rootDir, Map<String, String?> outputFilesAtStart) {
  return _expectFileTree(rootDir, {
    'hello.b64.txt': 'aGVsbG8=',
    path.join('more', 'foo.b64.txt'): 'Zm9v',
    ...outputFilesAtStart.map(
        (p, contents) => MapEntry(path.relative(p, from: rootDir), contents))
  });
}

Future<void> _expectFileTree(
    String rootDir, Map<String, String?> fileTree) async {
  for (final entry in fileTree.entries) {
    if (entry.value == null) continue;
    final file = File(path.join(rootDir, entry.key));
    expect(await file.exists(), isTrue,
        reason: 'file ${entry.key} does not exist');
    expect(await file.readAsString(), equals(entry.value),
        reason: 'file ${entry.key} has incorrect contents');
  }

  // make sure no extra files exist
  await for (final entity in Directory(rootDir).list(recursive: true)) {
    if (entity is File &&
        !fileTree.containsKey(path.relative(entity.path, from: rootDir))) {
      fail('Unexpected file in outputDir: ${entity.path}');
    }
  }
}

Future<void> _rebuildFileTree(Map<String, String?> fileTree) async {
  for (final entry in fileTree.entries) {
    final contents = entry.value;
    if (contents == null) {
      await Directory(entry.key).create();
    } else {
      await File(entry.key).writeAsString(contents, flush: true);
    }
  }
}
