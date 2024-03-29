import 'dart:io';

import 'package:args/args.dart';
import 'package:logging/logging.dart' as log;

import '_log.dart';
import 'dartle_version.g.dart';
import 'error.dart';

/// Dartle configuration options.
class Options {
  final log.Level logLevel;
  final bool colorfulLog;
  final bool showHelp;
  final bool showVersion;
  final bool showTasks;
  final bool showTaskGraph;
  final bool forceTasks;
  final bool parallelizeTasks;
  final bool resetCache;
  final bool logBuildTime;
  final bool runPubGet;
  final bool disableCache;
  final List<String> tasksInvocation;

  const Options({
    this.logLevel = log.Level.INFO,
    this.colorfulLog = true,
    this.showHelp = false,
    this.showVersion = false,
    this.showTasks = false,
    this.showTaskGraph = false,
    this.forceTasks = false,
    this.parallelizeTasks = true,
    this.resetCache = false,
    this.logBuildTime = true,
    this.runPubGet = true,
    this.disableCache = false,
    this.tasksInvocation = const [],
  });

  /// Whether any of the informational options is true.
  bool get showInfoOnly =>
      showTasks || showTaskGraph || showHelp || showVersion;

  /// Convert this options object to the equivalent command-line arguments.
  List<String> toArgs({bool includeTasks = true}) {
    return [
      '-l',
      (nameByLevel[logLevel] ?? 'info').toLowerCase(),
      if (!colorfulLog) '--no-color',
      if (forceTasks) '-f',
      if (!parallelizeTasks) '--no-parallel-tasks',
      if (showTasks) '-s',
      if (showTaskGraph) '-g',
      if (resetCache) '-z',
      if (showVersion) '-v',
      if (showHelp) '-h',
      if (!logBuildTime) '--no-log-build-time',
      if (includeTasks) ...tasksInvocation,
    ];
  }

  @override
  String toString() {
    return 'Options{logLevel: $logLevel, colorfulLog: $colorfulLog, '
        'showHelp: $showHelp, showVersion: $showVersion, showTasks: $showTasks, '
        'showTaskGraph: $showTaskGraph, forceTasks: $forceTasks, '
        'parallelizeTasks: $parallelizeTasks, resetCache: $resetCache, '
        'logBuildTime: $logBuildTime, runPubGet: $runPubGet, '
        'disableCache: $disableCache, tasksInvocation: $tasksInvocation}';
  }
}

final _parser = ArgParser()
  ..addOption(
    'log-level',
    abbr: 'l',
    defaultsTo: 'info',
    help: 'Set the log level.',
    allowed: levelByName.keys,
  )
  ..addFlag(
    'color',
    abbr: 'c',
    negatable: true,
    defaultsTo: true,
    help: 'Use ANSI colors to colorize output.',
  )
  ..addFlag(
    'force-tasks',
    abbr: 'f',
    negatable: false,
    help: 'Force all selected tasks to run.',
  )
  ..addFlag(
    'parallel-tasks',
    abbr: 'p',
    negatable: true,
    defaultsTo: true,
    help: 'Allow tasks to run in parallel using Isolates.',
  )
  ..addFlag(
    'show-tasks',
    abbr: 's',
    negatable: false,
    help: 'Show all tasks in this build. Does not run any tasks when enabled.',
  )
  ..addFlag(
    'show-task-graph',
    abbr: 'g',
    negatable: false,
    help: 'Show the task graph for this build. '
        'Does not run any tasks when enabled.',
  )
  ..addFlag(
    'reset-cache',
    abbr: 'z',
    negatable: false,
    help: 'Reset the Dartle cache.',
  )
  ..addFlag(
    'version',
    abbr: 'v',
    negatable: false,
    help: 'Show the Dartle version.',
  )
  ..addFlag(
    'help',
    abbr: 'h',
    negatable: false,
    help: 'Show this help message.',
  )
  ..addFlag(
    'log-build-time',
    negatable: true,
    defaultsTo: true,
    hide: true,
    help: 'Whether to log build time.',
  )
  ..addFlag(
    'run-pub-get',
    negatable: true,
    defaultsTo: true,
    hide: true,
    help: 'Whether to run "dart pub get" if dependencies not downloaded.',
  )
  ..addFlag(
    'disable-cache',
    negatable: false,
    abbr: 'd',
    defaultsTo: false,
    help: 'Whether to disable the Dartle cache.',
  );

/// Dartle usage message.
String get dartleUsage => '''
Dartle $dartleVersion

https://github.com/renatoathaydes/dartle

Usage: dartle [<options>] [<tasks>]

Runs a Dartle build.
Tasks are declared in the dartle.dart file. If no task is given, the
default tasks are run.

Options:
${_parser.usage}
''';

/// String describing Dartle's command-line options.
String optionsDescription = _parser.usage;

/// Parse the given args, setting the options as appropriate and returning the
/// tasks the user requested to run.
///
/// This method may be called several times with the same arguments without
/// actually parsing them again as the results of a first invocation are
/// cached, allowing different entry points of the library to call this
/// method to initialize the user options without re-parsing arguments every
/// time.
Options parseOptions(List<String> args) {
  ArgResults parseResult;
  try {
    parseResult = _parser.parse(args);
  } on FormatException catch (e) {
    throw DartleException(
        message: '${e.message}.. run with the -h flag to see usage.',
        exitCode: 4);
  }

  if (parseResult.wasParsed('help')) {
    return const Options(showHelp: true);
  }
  if (parseResult.wasParsed('version')) {
    return const Options(showVersion: true);
  }
  var colorOption = parseResult['color'] as bool;
  if (!parseResult.wasParsed('color') && isNoColorEnvVarSet()) {
    colorOption = false;
  }

  return Options(
    logLevel: _parseLogLevel(parseResult['log-level'].toString()),
    colorfulLog: colorOption,
    forceTasks: parseResult['force-tasks'] as bool,
    parallelizeTasks: parseResult['parallel-tasks'] as bool,
    showTasks: parseResult['show-tasks'] as bool,
    showTaskGraph: parseResult['show-task-graph'] as bool,
    resetCache: parseResult['reset-cache'] as bool,
    logBuildTime: parseResult['log-build-time'] as bool,
    runPubGet: parseResult['run-pub-get'] as bool,
    disableCache: parseResult['disable-cache'] as bool,
    tasksInvocation: parseResult.rest,
  );
}

/// Checks if the NO_COLOR environment variable is set.
///
/// See https://no-color.org/
bool isNoColorEnvVarSet() {
  final noColor = Platform.environment['NO_COLOR'];
  return noColor != null && noColor.isNotEmpty;
}

log.Level _parseLogLevel(String value) {
  final logLevel = levelByName[value];
  if (logLevel == null) {
    throw StateError('Invalid log level: $value');
  }
  return logLevel;
}
