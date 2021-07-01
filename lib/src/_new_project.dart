import 'dart:io';

import '_log.dart';
import 'dartle_version.g.dart';
import 'error.dart';
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

Future<void> createNewProject() async {
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
