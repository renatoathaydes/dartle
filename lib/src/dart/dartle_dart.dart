import 'dart:io';

import 'package:dartle/dartle.dart';
import 'package:path/path.dart' show extension, join, dirname;

/// Configuration for the [DartleDart] class.
class DartConfig {
  /// Whether or not to include the "analyzeCode" task in the build.
  final bool runAnalyzer;

  /// Whether or not to include the "format" task in the build.
  final bool formatCode;

  /// Whether or not to include the "runBuildRunner" task in the build.
  final bool runBuildRunner;

  /// Whether or not to include the "test" task in the build.
  final bool runTests;

  /// Project's root directory (location of dartle.dart file, by default).
  final String? rootDir;

  const DartConfig({
    this.runAnalyzer = true,
    this.formatCode = true,
    this.runBuildRunner = false,
    this.runTests = true,
    this.rootDir,
  });
}

/// Dartle built-in functionality for Dart projects.
///
/// To use it, include [DartleDart.tasks] in the build as follows:
///
/// ```dart
/// final dartleDart = DartleDart();
///
/// void main(List<String> args) {
///   run(args, tasks: {
///     ...dartleDart.tasks,
///   }, defaultTasks: {
///     dartleDart.build
///   });
/// }
/// ```
///
/// If you want to configure [DartleDart], pass an instance of [DartConfig]
/// via its constructor.
class DartleDart {
  final DartConfig config;

  late final Task formatCode, runBuildRunner, analyzeCode, test, build, clean;

  /// Get the tasks that are configured as part of a build.
  Set<Task> get tasks {
    return {
      if (config.formatCode) formatCode,
      if (config.runAnalyzer) analyzeCode,
      if (config.runBuildRunner) runBuildRunner,
      if (config.runTests) test,
      build,
      clean,
    };
  }

  /// The project's root directory.
  ///
  /// By default, this directory is the same as the one where the dartle.dart
  /// script is located, but you can change it via [DartConfig.rootDir].
  final String rootDir;

  DartleDart([DartConfig config = const DartConfig()])
      : config = config,
        rootDir = config.rootDir ?? dirname(Platform.script.toFilePath()) {
    final allDartFiles = dir(rootDir, fileFilter: dartFileFilter);
    final testDartFiles =
        dir(join(rootDir, 'test'), fileFilter: dartFileFilter);

    formatCode = Task(_formatCode,
        name: 'format',
        description: 'Formats all Dart source code',
        runCondition: RunOnChanges(inputs: allDartFiles));

    runBuildRunner = Task(_runBuildRunner,
        name: 'runBuildRunner',
        description: 'Runs the Dart build_runner tool',
        dependsOn: {'generateDartSources'},
        runCondition: RunOnChanges(inputs: testDartFiles));

    analyzeCode = Task(_analyzeCode,
        name: 'analyzeCode',
        description: 'Analyzes Dart source code',
        runCondition: RunOnChanges(inputs: allDartFiles));

    test = Task(_test,
        name: 'test',
        description: 'Runs all tests. Arguments can be used to provide the '
            'platforms the tests should run on.',
        dependsOn: {if (config.runAnalyzer) 'analyzeCode'},
        argsValidator: const AcceptAnyArgs(),
        runCondition: RunOnChanges(
            inputs: dirs(const ['lib', 'bin', 'test', 'example'])));

    clean = Task(
        (_) async => await ignoreExceptions(() => deleteOutputs(tasks)),
        name: 'clean',
        description: 'Deletes the outputs of all other tasks in this build');

    build = Task((_) => null, // no action, just grouping other tasks
        name: 'build',
        description: 'Runs all enabled tasks');

    build.dependsOn =
        tasks.where((t) => t != build && t != clean).map((t) => t.name).toSet();
  }

  Future<void> _test(List<String> platforms) async {
    final platformArgs = platforms.expand((p) => ['-p', p]);
    final code = await execProc(
        Process.start('pub', ['run', 'test', ...platformArgs]),
        name: 'Dart Tests');
    if (code != 0) failBuild(reason: 'Tests failed');
  }

  Future<void> _formatCode(_) async {
    final code = await execProc(Process.start('dartfmt', const ['-w', '.']),
        name: 'Dart Formatter');
    if (code != 0) failBuild(reason: 'Dart Formatter failed');
  }

  Future<void> _runBuildRunner(_) async {
    final code = await execProc(
      Process.start('dart', const ['run', 'build_runner', 'build']),
      name: 'Dart Analyzer',
      successMode: StreamRedirectMode.stdout_stderr,
    );
    if (code != 0) failBuild(reason: 'Dart Analyzer failed');
  }

  Future<void> _analyzeCode(_) async {
    final code = await execProc(Process.start('dart', const ['analyze', '.']),
        name: 'Dart Analyzer', successMode: StreamRedirectMode.stdout_stderr);
    if (code != 0) failBuild(reason: 'Dart Analyzer failed');
  }
}

/// Return true for files with the `.dart` extension, false otherwise.
FileFilter dartFileFilter = (f) => extension(f.path) == '.dart';
