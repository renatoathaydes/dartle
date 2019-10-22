import 'dart:io';

import 'package:args/args.dart';
import 'package:logging/logging.dart' as log;

import '_log.dart';
import 'helpers.dart';

class _Options {
  final log.Level logLevel;
  final bool forceTasks;

  const _Options({this.logLevel = log.Level.INFO, this.forceTasks = false});
}

_Options _options = const _Options();

class _ParsedArguments {
  final _Options options;
  final List<String> taskNames;

  const _ParsedArguments(this.options, this.taskNames);
}

bool get forceTasksOption => _options.forceTasks;

// allows calling [parseOptionsAndGetTasks] more than once without actually
// parsing all arguments again.
final Map<String, _ParsedArguments> _argsCache = {};

log.Level _parseLogLevel(String value) {
  final logLevel = levelByName[value];
  if (logLevel == null) {
    throw StateError("Invalid log level: $value");
  }
  return logLevel;
}

/// Parse the given args, setting the options as appropriate and returning the
/// tasks the user requested to run.
///
/// This method may be called several times with the same arguments without
/// actually parsing them again as the results of a first invocation are
/// cached, allowing different entry points of the library to call this
/// method to initialize the user options without re-parsing arguments every
/// time.
List<String> parseOptionsAndGetTasks(List<String> args) {
  final argsCacheKey = "$args";
  final parsedArgs = _argsCache[argsCacheKey];
  if (parsedArgs != null) return parsedArgs.taskNames;
  final parser = ArgParser()
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
      'help',
      abbr: 'h',
      negatable: false,
      help: 'show this help message',
    );
  ArgResults parseResult;
  try {
    parseResult = parser.parse(args);
  } on FormatException catch (e) {
    return failBuild(reason: '${e.message}\nUsage:\n${parser.usage}')
        as List<String>;
  }

  if (parseResult.wasParsed('help')) {
    print("Usage: dartle [<options>] [<tasks>]\n\n"
        "Runs a Dartle build.\n"
        "Tasks are declared in the dartle.dart file. If no task is given, the "
        "default tasks are run.\n\nOptions:");
    print(parser.usage);
    exit(0);
    return const [];
  }

  _options = _Options(
    logLevel: _parseLogLevel(parseResult['log-level'].toString()),
    forceTasks: parseResult.wasParsed('force-tasks'),
  );

  setLogLevel(_options.logLevel);

  _argsCache[argsCacheKey] = _ParsedArguments(_options, parseResult.rest);

  return parseResult.rest;
}
