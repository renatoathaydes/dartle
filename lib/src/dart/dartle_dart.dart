import 'dart:io';

import 'package:path/path.dart';
import 'package:yaml/yaml.dart';

import '../../dartle_cache.dart';
import '../_utils.dart' as utils;
import '../helpers.dart';
import '../run_condition.dart';
import '../task.dart';
import '../task_run.dart' show ChangeSet;
import '_dart_tests.dart';

/// Configuration for the [DartleDart] class.
class DartConfig {
  /// Whether or not to include the "analyzeCode" task in the build.
  final bool runAnalyzer;

  /// Whether or not to include the "format" task in the build.
  final bool formatCode;

  /// Whether or not to include the "test" task in the build.
  final bool runTests;

  /// Whether or not to include the "compileExe" task in the build.
  final bool compileExe;

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
    this.compileExe = true,
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
      compileExe,
      clean;

  final bool _enableBuildRunner;

  /// Get the tasks that are configured as part of a build.
  ///
  /// The returned Set is immutable.
  late final Set<Task> tasks;

  /// The project's root directory.
  ///
  /// By default, this directory is the working directory, but you can change
  /// it via [DartConfig.rootDir].
  final String rootDir;

  DartleDart([this.config = const DartConfig()])
      : rootDir = config.rootDir ?? '.',
        _enableBuildRunner = config.buildRunnerRunCondition != null {
    final allDartFiles = dir(rootDir,
        exclusions: const {'build'}, fileExtensions: const {'dart'});
    final productionDartFiles =
        dirs(['lib', 'bin'], fileExtensions: const {'dart'});

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

    compileExe = Task(_compileExe,
        name: 'compileExe',
        description: 'Compiles Dart executables declared in pubspec. '
            'Argument may specify the name(s) of the executable(s) to compile.',
        dependsOn: {'analyzeCode'},
        argsValidator: const AcceptAnyArgs(),
        runCondition: RunOnChanges(
            inputs: productionDartFiles, outputs: dir('$rootDir/build/bin')));

    runPubGet = Task(utils.runPubGet,
        name: 'runPubGet',
        description: 'Runs "pub get" in order to update dependencies.',
        runCondition: OrCondition([
          RunAtMostEvery(config.runPubGetAtMostEvery),
          RunOnChanges(
              inputs: files(['$rootDir/pubspec.yaml', '$rootDir/pubspec.lock']))
        ]));

    test = Task(_test,
        name: 'test',
        description: 'Runs Dart tests.',
        dependsOn: {if (config.runAnalyzer) 'analyzeCode'},
        argsValidator: const TestTaskArgsValidator(),
        runCondition: RunOnChanges(
            inputs: dirs(['lib', 'bin', 'test', 'example']
                .map((e) => join(rootDir, e)))));

    final buildTasks = {
      if (config.formatCode) formatCode,
      if (config.runAnalyzer) analyzeCode,
      if (config.compileExe) compileExe,
      if (_enableBuildRunner) runBuildRunner,
      if (config.runTests) test,
      runPubGet,
    };

    clean = createCleanTask(
        tasks: buildTasks,
        name: 'clean',
        description: 'Deletes the outputs of all other tasks in this build.');

    build = Task((_) => null, // no action, just grouping other tasks
        name: 'build',
        description: 'Runs all enabled tasks.');

    build.dependsOn(buildTasks
        // exclude tasks already added into buildTasks but that
        // should not run by default
        .where((t) => t != compileExe)
        .map((t) => t.name)
        .toSet());

    buildTasks.add(clean);
    buildTasks.add(build);

    tasks = Set.unmodifiable(buildTasks);
  }

  Future<void> _test(List<String> args, [ChangeSet? changes]) async {
    final options = args.where((a) => a != '--all');
    final forceAllTests = args.contains('--all') ||
        // if it looks like a file or dir was included in args, avoid trying
        // to specify which tests to run.
        args.any((a) => a.contains(Platform.pathSeparator));

    final testChanges = changes?.inputChanges
            .where((change) => change.entity.path.endsWith('_test.dart'))
            .toList() ??
        const [];

    List<String> testsToRun;

    if (!forceAllTests &&
        testChanges.isNotEmpty &&
        testChanges.length == changes!.inputChanges.length) {
      // only tests have changed, run the changed tests only!
      testsToRun = testChanges
          .where((change) =>
              change.kind != ChangeKind.deleted && change.entity is File)
          .map((change) => change.entity.path)
          .toList();
    } else {
      testsToRun = const [];
    }

    await runTests(options, config.testOutput, testsToRun);
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

  Future<void> _compileExe(List<String> args) async {
    bool Function(String) filter =
        args.isEmpty ? ((String s) => true) : args.contains;
    final yaml = loadYaml(await File('pubspec.yaml').readAsString());
    final executables = yaml['executables'] as Map;
    final srcDir = join(rootDir, 'bin');
    final targetDir = join(rootDir, 'build', 'bin');
    await Directory(targetDir).create(recursive: true);
    final futures = executables.map((name, file) {
      name as String;
      file as String?;
      if (!filter(name)) return MapEntry('', Future.value(0));
      final src = join(
          srcDir, file == null || file.isEmpty ? '$name.dart' : '$file.dart');
      final executable =
          join(targetDir, '$name${Platform.isWindows ? '.exe' : ''}');
      final future = execProc(
          Process.start('dart', ['compile', 'exe', src, '-o', executable]),
          name: 'Dart compile exe',
          successMode: StreamRedirectMode.stdoutAndStderr);
      return MapEntry(name, future);
    });
    final compilable = futures.entries.where((e) => e.key.isNotEmpty).toList();
    if (compilable.isEmpty) {
      if (args.isEmpty) {
        failBuild(reason: 'No executables found in pubspec');
      }
      failBuild(reason: 'No executables named $args were found');
    }
    for (final entry in futures.entries) {
      final code = await entry.value;
      if (code != 0) failBuild(reason: 'Failed to compile ${entry.key}');
    }
  }
}

class TestTaskArgsValidator with ArgsValidator {
  const TestTaskArgsValidator();

  @override
  String helpMessage() => '''
The following options are accepted:

    --all     run all tests, even unmodified ones.
    
    Any other arguments are passed on to 'dart test'.
''';

  @override
  bool validate(List<String> args) => true;
}
