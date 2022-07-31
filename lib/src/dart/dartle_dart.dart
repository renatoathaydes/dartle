import 'dart:io';

import '../file_collection.dart';
import '../helpers.dart';
import '../run_condition.dart';
import '../task.dart';
import '_dart_tests.dart';

/// Configuration for the [DartleDart] class.
class DartConfig {
  /// Whether or not to include the "analyzeCode" task in the build.
  final bool runAnalyzer;

  /// Whether or not to include the "format" task in the build.
  final bool formatCode;

  /// Whether or not to include the "test" task in the build.
  final bool runTests;

  /// Project's root directory (location of dartle.dart file, by default).
  final String? rootDir;

  /// Period of time after which `pub get` should be run.
  final Duration runPubGetAtMostEvery;

  /// The type of outputs to use for tests.
  final DartTestOutput testOutput;

  /// The [RunCondition] for the buildRunner task.
  ///
  /// Setting this to a non-null value causes the `runBuildRunner` task to be
  /// enabled.
  final RunCondition? buildRunnerRunCondition;

  const DartConfig({
    this.runAnalyzer = true,
    this.formatCode = true,
    this.runTests = true,
    this.runPubGetAtMostEvery = const Duration(days: 5),
    this.rootDir,
    this.testOutput = DartTestOutput.dartleReporter,
    this.buildRunnerRunCondition,
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

  late final Task formatCode,
      runBuildRunner,
      analyzeCode,
      runPubGet,
      test,
      build,
      clean;

  final bool _enableBuildRunner;

  /// Get the tasks that are configured as part of a build.
  Set<Task> get tasks {
    return {
      if (config.formatCode) formatCode,
      if (config.runAnalyzer) analyzeCode,
      if (_enableBuildRunner) runBuildRunner,
      if (config.runTests) test,
      runPubGet,
      build,
      clean,
    };
  }

  /// The project's root directory.
  ///
  /// By default, this directory is the working directory, but you can change
  /// it via [DartConfig.rootDir].
  final String rootDir;

  DartleDart([this.config = const DartConfig()])
      : rootDir = config.rootDir ?? '.',
        _enableBuildRunner = config.buildRunnerRunCondition != null {
    final allDartFiles = dir(rootDir, fileExtensions: const {'dart'});

    formatCode = Task(_formatCode,
        name: 'format',
        dependsOn: {if (_enableBuildRunner) 'runBuildRunner'},
        description: 'Formats all Dart source code.',
        runCondition: RunOnChanges(inputs: allDartFiles));

    runBuildRunner = Task(_runBuildRunner,
        name: 'runBuildRunner',
        description: 'Runs the Dart build_runner tool.',
        dependsOn: {'runPubGet'},
        runCondition: config.buildRunnerRunCondition ?? const AlwaysRun());

    analyzeCode = Task(_analyzeCode,
        name: 'analyzeCode',
        dependsOn: {
          'runPubGet',
          if (config.formatCode) 'format',
          if (_enableBuildRunner) 'runBuildRunner',
        },
        description: 'Analyzes Dart source code',
        runCondition: RunOnChanges(inputs: allDartFiles));

    runPubGet = Task(_runPubGet,
        name: 'runPubGet',
        description: 'Runs "pub get" in order to update dependencies.',
        runCondition: OrCondition([
          RunAtMostEvery(config.runPubGetAtMostEvery),
          RunOnChanges(inputs: files(const ['pubspec.yaml', 'pubspec.lock']))
        ]));

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
        phase: TaskPhase.setup,
        description: 'Deletes the outputs of all other tasks in this build.');

    build = Task((_) => null, // no action, just grouping other tasks
        name: 'build',
        description: 'Runs all enabled tasks.');

    build.dependsOn(tasks
        .where((t) => t != build && t != clean)
        .map((t) => t.name)
        .toSet());
  }

  Future<void> _test(List<String> platforms) async {
    final platformArgs = platforms.expand((p) => ['-p', p]);
    await runTests(platformArgs, config.testOutput);
  }

  Future<void> _formatCode(_) async {
    final code = await execProc(Process.start('dart', const ['format', '.']),
        name: 'Dart Formatter');
    if (code != 0) failBuild(reason: 'Dart Formatter failed');
  }

  Future<void> _runBuildRunner(_) async {
    final code = await execProc(
      Process.start('dart', const ['run', 'build_runner', 'build']),
      name: 'Dart Analyzer',
      successMode: StreamRedirectMode.stdoutAndStderr,
    );
    if (code != 0) failBuild(reason: 'Dart Analyzer failed');
  }

  Future<void> _analyzeCode(_) async {
    final code = await execProc(Process.start('dart', const ['analyze', '.']),
        name: 'Dart Analyzer', successMode: StreamRedirectMode.stdoutAndStderr);
    if (code != 0) failBuild(reason: 'Dart Analyzer failed');
  }

  Future<void> _runPubGet(_) async {
    final code = await execProc(Process.start('dart', const ['pub', 'get']),
        name: 'Dart pub get', successMode: StreamRedirectMode.stdoutAndStderr);
    if (code != 0) failBuild(reason: 'Dart "pub get"" failed');
  }
}
