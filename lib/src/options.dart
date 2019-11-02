import 'package:args/args.dart';
import 'package:logging/logging.dart' as log;

import '_log.dart';
import 'error.dart';

class Options {
  final log.Level logLevel;
  final bool forceTasks;
  final bool showHelp;
  final bool resetCache;
  final List<String> requestedTasks;

  const Options(
      {this.logLevel = log.Level.INFO,
      this.showHelp = false,
      this.forceTasks = false,
      this.resetCache = false,
      this.requestedTasks = const []});
}

final _parser = ArgParser()
  ..addOption(
    'log-level',
    abbr: 'l',
    defaultsTo: 'info',
    help: 'sets the log level',
    allowed: levelByName.keys,
  )
  ..addFlag(
    'force-tasks',
    abbr: 'f',
    negatable: false,
    help: 'Force all selected tasks to run',
  )
  ..addFlag(
    'reset-cache',
    abbr: 'z',
    negatable: false,
    help: 'Reset the Dartle cache',
  )
  ..addFlag(
    'help',
    abbr: 'h',
    negatable: false,
    help: 'show this help message',
  );

/// Dartle usage message.
String get dartleUsage => """
Usage: dartle [<options>] [<tasks>]

Runs a Dartle build.
Tasks are declared in the dartle.dart file. If no task is given, the
default tasks are run.

Options:
${_parser.usage}
""";

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
        message: '${e.message}\nUsage:\n${_parser.usage}',
        exitCode: 4);
  }

  if (parseResult.wasParsed('help')) {
    return const Options(showHelp: true);
  }

  return Options(
    logLevel: _parseLogLevel(parseResult['log-level'].toString()),
    forceTasks: parseResult.wasParsed('force-tasks'),
    requestedTasks: parseResult.rest,
    resetCache: parseResult.wasParsed('reset-cache'),
  );
}

log.Level _parseLogLevel(String value) {
  final logLevel = levelByName[value];
  if (logLevel == null) {
    throw StateError("Invalid log level: $value");
  }
  return logLevel;
}
