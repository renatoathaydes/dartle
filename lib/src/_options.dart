import 'dart:io';

import 'package:args/args.dart';

import 'helpers.dart';

enum LogLevel { fine, debug, info, warn, error }

const logLevels = {
  'fine': LogLevel.fine,
  'debug': LogLevel.debug,
  'info': LogLevel.info,
  'warn': LogLevel.warn,
  'error': LogLevel.error,
};

class _Options {
  final LogLevel logLevel;

  const _Options({this.logLevel = LogLevel.info});
}

_Options _options = const _Options();

bool isLogEnabled(LogLevel logLevel) =>
    _options.logLevel.index <= logLevel.index;

LogLevel _parseLogLevel(String value) {
  final logLevel = logLevels[value];
  if (logLevel == null) {
    throw StateError("Invalid log level: $value");
  }
  return logLevel;
}

List<String> parseOptionsAndGetTasks(List<String> args) {
  final parser = ArgParser()
    ..addOption(
      'log-level',
      abbr: 'l',
      defaultsTo: 'info',
      help: 'sets the log level',
      allowed: logLevels.keys,
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'show this usage help message',
    );
  ArgResults parseResult;
  try {
    parseResult = parser.parse(args);
  } on FormatException catch (e) {
    return failBuild(reason: 'ERROR: ${e.message}\nUsage:\n${parser.usage}')
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
  );

  return parseResult.rest;
}
