import 'dart:io';

import 'package:args/args.dart';
import 'package:logging/logging.dart' as log;

import '_log.dart';
import 'helpers.dart';

class _Options {
  final log.Level logLevel;

  const _Options({this.logLevel = log.Level.INFO});
}

_Options _options = const _Options();

log.Level _parseLogLevel(String value) {
  final logLevel = levelByName[value];
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
      allowed: levelByName.keys,
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
  );

  setLogLevel(_options.logLevel);

  return parseResult.rest;
}
