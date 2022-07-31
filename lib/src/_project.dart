import 'dart:io';

import 'package:logging/logging.dart' as log;

import '_log.dart';
import 'error.dart';
import 'core.dart' show dartleFileMissingMessage;
import 'dartle_version.g.dart';
import 'helpers.dart';

const _basicDartleFile = r'''
import 'package:dartle/dartle.dart';

/// The task name is the name of the function given to it unless overridden
final sampleTask = Task(sample,
    description: 'Sample Task',
    // This task will only run if the inputs/outputs changed
    // since the last time it ran
    runCondition: RunOnChanges(inputs: dir('source'), outputs: dir('target')));

void main(List<String> args) {
  run(args, tasks: {
    sampleTask,
  }, defaultTasks: {
    sampleTask,
  });
}

Future<void> sample(_) async {
  print('Hello Dartle!');
}
''';

const _dartDartleFile = '''
import 'package:dartle/dartle_dart.dart';

final dartleDart = DartleDart();

void main(List<String> args) {
  run(args, tasks: {
    ...dartleDart.tasks,
  }, defaultTasks: {
    dartleDart.build
  });
}
''';

const _basicPubSpec = '''
name: dartle_project
description: Builds this project
version: 0.0.0
publish_to: none

environment:
  sdk: '>=2.12.0 <3.0.0'

dev_dependencies:
  dartle: ^$dartleVersion
''';

Never abort(int code) {
  exit(code);
}

Future<void> onNoDartleFile(bool doNotExit) async {
  if (logger.isLoggable(log.Level.INFO)) {
    stdout.write('There is no dartle.dart file in the current directory.\n'
        'Would you like to create one [y/N]? ');
  } else {}
  final answer = stdin.readLineSync()?.toLowerCase();
  if (answer == 'y' || answer == 'yes') {
    await _createNewProject();
  } else if (doNotExit) {
    throw DartleException(message: dartleFileMissingMessage, exitCode: 4);
  } else {
    logger.severe(dartleFileMissingMessage);
    abort(4);
  }
}

Future<void> _createNewProject() async {
  logger.fine('Creating new Dartle project');
  final pubspecFile = File('pubspec.yaml');
  if (await pubspecFile.exists()) {
    logger.fine(
        'pubspec alread exists, creating Dartle Project with Dart support');
    await File('dartle.dart').writeAsString(_dartDartleFile, flush: true);

    final code = await exec(
        Process.start('dart', const ['pub', 'add', '--dev', 'dartle']));
    if (code != 0) {
      throw DartleException(
          message: '"dart pub add" program failed with code $code');
    }
  } else {
    logger.fine('pubspec does not exist, creating basic Dartle Project');
    await pubspecFile.writeAsString(_basicPubSpec, flush: true);
    await File('dartle.dart').writeAsString(_basicDartleFile, flush: true);
  }
  logger.fine('Installing new project\'s dependencies');
  final code = await exec(Process.start('dart', const ['pub', 'get']));
  if (code != 0) {
    throw DartleException(
        message: '"dart pub get" program failed with code $code');
  }
}
