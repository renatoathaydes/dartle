import 'dart:io';

import 'package:dartle/dartle.dart';
import 'package:path/path.dart' show extension;

import 'dartle-src/metadata_generator.dart' show generateVersionDartFile;

FileFilter dartFileFilter = (f) => extension(f.path) == '.dart';

final libDirDartFiles = dir('lib', fileFilter: dartFileFilter);
final allDartFiles = dir('.', fileFilter: dartFileFilter);

final generateDartleVersionFileTask = Task(
    (_) async =>
        await generateVersionDartFile(File('lib/src/dartle_version.g.dart')),
    name: 'generateDartSources',
    description: 'Generates Dart source files');

final checkImportsTask = Task(checkImports,
    description: 'Checks dart file imports are allowed',
    runCondition: RunOnChanges(inputs: libDirDartFiles));

final formatCodeTask = Task(formatCode,
    description: 'Formats all Dart source code',
    runCondition: RunOnChanges(inputs: allDartFiles));

final analyzeCodeTask = Task(analyzeCode,
    description: 'Analyzes Dart source code',
    dependsOn: {'generateDartSources'},
    runCondition: RunOnChanges(inputs: allDartFiles));

final testTask = Task(test,
    description: 'Runs all tests. Arguments can be used to provide the '
        'platforms the tests should run on.',
    dependsOn: {'analyzeCode'},
    argsValidator: const AcceptAnyArgs(),
    runCondition:
        RunOnChanges(inputs: dirs(const ['lib', 'bin', 'test', 'example'])));

final verifyTask = Task((_) => null, // no action, just grouping other tasks
    name: 'verify',
    description: 'Verifies code style and linters, runs tests',
    dependsOn: {'checkImports', 'formatCode', 'analyzeCode', 'test'});

final cleanTask = Task(
    (_) async => await ignoreExceptions(
        () => deleteOutputs({testTask, generateDartleVersionFileTask})),
    name: 'clean',
    description: 'Deletes the outputs of all other tasks');

void main(List<String> args) => run(args, tasks: {
      cleanTask,
      generateDartleVersionFileTask,
      checkImportsTask,
      formatCodeTask,
      analyzeCodeTask,
      testTask,
      verifyTask,
    }, defaultTasks: {
      verifyTask
    });

test(List<String> platforms) async {
  final platformArgs = platforms.expand((p) => ['-p', p]);
  final code = await execProc(
      Process.start('pub', ['run', 'test', ...platformArgs]),
      name: 'Dart Tests');
  if (code != 0) failBuild(reason: 'Tests failed');
}

checkImports(_) async {
  await for (final file in libDirDartFiles.files) {
    final illegalImports = (await file.readAsLines()).where(
        (line) => line.contains(RegExp("^import\\s+['\"]package:dartle")));
    if (illegalImports.isNotEmpty) {
      failBuild(
          reason: 'File ${file.path} contains '
              'self import to the dartle package: ${illegalImports}');
    }
  }
}

formatCode(_) async {
  final code = await execProc(Process.start('dartfmt', const ['-w', '.']),
      name: 'Dart Formatter');
  if (code != 0) failBuild(reason: 'Dart Formatter failed');
}

analyzeCode(_) async {
  final code = await execProc(Process.start('dartanalyzer', const ['.']),
      name: 'Dart Analyzer', successMode: StreamRedirectMode.stdout_stderr);
  if (code != 0) failBuild(reason: 'Dart Analyzer failed');
}
