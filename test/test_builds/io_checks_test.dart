import 'dart:io';

import 'package:dartle/dartle.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../test_utils.dart';
import 'io_checks/dartle.dart';

const _buildDirectory = 'test/test_builds/io_checks';

const oneTaskExecutingMessage = 'Executing 1 task out of a total of 1 task:'
    ' 1 task selected';
const oneOfTwoTasksExecutingMessage =
    'Executing 1 task out of a total of 2 tasks:'
    ' 1 task selected';

const noTasksOfOneExecutingMessage =
    'Executing 0 tasks out of a total of 1 task:'
    ' 1 task selected, 1 up-to-date';
const noTasksOfTwoExecutingMessage =
    'Executing 0 tasks out of a total of 2 tasks:'
    ' 1 task selected, 1 up-to-date';

Future<void> _deleteDartleToolDir() async {
  await deleteAll(
      dir(path.join(_buildDirectory, '.dartle_tool'), includeHidden: true));
}

void main() {
  group('IO Checks', () {
    File buildExe = File('');
    final outputsDir = Directory(path.join(_buildDirectory, 'outputs'));
    final incOutputsDir = Directory(path.join(_buildDirectory, 'inc-outputs'));
    Map<String, String?> outputFilesAtStart = {};

    setUpAll(() async {
      buildExe =
          await createDartExe(File(path.join(_buildDirectory, 'dartle.dart')));
    });

    tearDownAll(() async {
      await deleteAll(file(buildExe.path));
    });

    setUp(() async {
      await _deleteDartleToolDir();
      final preExistingOutput = outputsDir.list(recursive: true);
      await for (final out in preExistingOutput) {
        outputFilesAtStart[path.relative(out.path, from: outputsDir.path)] =
            (out is File) ? await out.readAsString() : null;
      }
    });

    tearDown(() async {
      await _deleteDartleToolDir();
      await ignoreExceptions(
          () async => await outputsDir.delete(recursive: true));
      await ignoreExceptions(
          () async => await incOutputsDir.delete(recursive: true));
      await outputsDir.create();
      await _rebuildFileTree(outputFilesAtStart);
    });

    Future<ProcessResult> runExampleDartBuild(List<String> args) async {
      return startProcess(
          runDartExe(buildExe, args: args, workingDirectory: _buildDirectory),
          'io_checks test dart build');
    }

    test('can run simple task and produce expected outputs', () async {
      var proc = await runExampleDartBuild(const ['--no-color', 'base64']);
      expect(proc.exitCode, equals(0));
      expect(proc.stdout[0], contains(oneOfTwoTasksExecutingMessage));
      expect(proc.stderr, isEmpty);
      await _expectFileTreeAfterBase64TaskRuns(
          outputsDir.path, outputFilesAtStart);
    });

    test('running second time skips the cached task', () async {
      var proc = await runExampleDartBuild(const ['--no-color', 'base64']);
      expect(proc.exitCode, equals(0));

      // run again
      proc = await runExampleDartBuild(const ['--no-color', 'base64']);
      expect(proc.exitCode, equals(0));

      expect(proc.stdout[0], contains(noTasksOfTwoExecutingMessage));
      expect(proc.stderr, isEmpty);
      await _expectFileTreeAfterBase64TaskRuns(
          outputsDir.path, outputFilesAtStart);
    });

    test('running again time after change in inputs or outputs re-runs task',
        () async {
      final inputFile = File(path.join(
          _buildDirectory, inputs.directories.first.path, 'more', 'foo.txt'));
      final originalInputFileContents = await inputFile.readAsString();

      var proc = await runExampleDartBuild(const ['--no-color', 'base64']);
      expect(proc.exitCode, equals(0));

      // change an input file
      await inputFile.writeAsString('not foo', flush: true);

      Future<void> revertInputFileChange() =>
          inputFile.writeAsString(originalInputFileContents, flush: true);

      // revert the change later even if test fails
      addTearDown(revertInputFileChange);

      // run again
      proc = await runExampleDartBuild(const ['--no-color', 'base64']);
      expect(proc.exitCode, equals(0));
      expect(proc.stdout[0], contains(oneOfTwoTasksExecutingMessage));
      expect(proc.stderr, isEmpty);

      // change an output file
      await File(path.join(outputsDir.path, 'hello.b64.txt'))
          .writeAsString('changed this', flush: true);

      // run again
      proc = await runExampleDartBuild(const ['--no-color', 'base64']);
      expect(proc.exitCode, equals(0));
      expect(proc.stdout[0], contains(oneOfTwoTasksExecutingMessage));
      expect(proc.stderr, isEmpty);

      // reset input so the output should go back to the expected state
      await revertInputFileChange();

      // run again
      proc = await runExampleDartBuild(const ['--no-color', 'base64']);
      expect(proc.exitCode, equals(0));

      // finally, the outputs should be as expected after running the task again
      await _expectFileTreeAfterBase64TaskRuns(
          outputsDir.path, outputFilesAtStart);
    });

    test('incremental task', () async {
      var proc = await runExampleDartBuild(const ['--no-color', 'incremental']);
      expect(proc.exitCode, equals(0), reason: 'STDOUT: ${proc.stdout}');
      expect(proc.stdout[0], contains(oneOfTwoTasksExecutingMessage));
      await expectFileTree(incOutputsDir.path, {
        'out.txt': ''
            'added: inc-inputs\n'
            'added: inc-inputs/bye.txt\n'
            'added: inc-inputs/hello.txt'
      });

      // run again (no changes)
      proc = await runExampleDartBuild(const ['--no-color', 'incremental']);
      expect(proc.exitCode, equals(0));

      expect(proc.stdout[0], contains(noTasksOfTwoExecutingMessage));
      expect(proc.stderr, isEmpty);

      // change one of the input files
      final inputFile = File(path.join(
          _buildDirectory, incInputs.directories.first.path, 'hello.txt'));
      final originalInputFileContents = await inputFile.readAsString();

      await inputFile.writeAsString('bye', flush: true);

      Future<void> revertInputFileChange() =>
          inputFile.writeAsString(originalInputFileContents, flush: true);

      // revert the change later even if test fails
      addTearDown(revertInputFileChange);

      // run again, ensure the input file change was detected
      proc = await runExampleDartBuild(const ['--no-color', 'incremental']);
      expect(proc.exitCode, equals(0), reason: 'STDOUT: ${proc.stdout}');
      expect(proc.stdout[0], contains(oneOfTwoTasksExecutingMessage));
      await expectFileTree(
          incOutputsDir.path, {'out.txt': 'modified: inc-inputs/hello.txt'});
    });
  });
}

Future<void> _expectFileTreeAfterBase64TaskRuns(
    String rootDir, Map<String, String?> outputFilesAtStart) {
  return expectFileTree(rootDir, {
    'hello.b64.txt': 'aGVsbG8=',
    path.join('more', 'foo.b64.txt'): 'Zm9v',
    ...outputFilesAtStart,
  });
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
