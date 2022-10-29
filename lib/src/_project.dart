import 'dart:io';

import 'package:logging/logging.dart' as log;
import 'package:path/path.dart' as p;

import '_log.dart';
import 'core.dart' show dartleFileMissingMessage;
import 'dartle_version.g.dart';
import 'error.dart';
import 'helpers.dart';

const _basicInputFile = r'''
Hello Dartle!
''';

const _basicTaskFile = r'''
import 'dart:io';

import 'package:dartle/dartle.dart';

/// The task name is the name of the function given to it unless overridden.
final sampleTask = Task(sample,
    description: 'Sample Task',
    // This task will only run if the inputs/outputs changed
    // since the last time it ran
    runCondition: RunOnChanges(inputs: dir('source'), outputs: dir('target')));

Future<void> sample(_) async {
  final inputFiles = await Directory('source').list(recursive: true).toList();
  await Directory('target').create();
  await File('target/output.txt')
      .writeAsString(inputFiles.map((e) => e.path).join('\n'));
}
''';

const _basicDartleFile = r'''
import 'package:dartle/dartle.dart';

import 'dartle-src/tasks.dart';

void main(List<String> args) {
  run(args, tasks: {
    sampleTask,
    createCleanTask(name: 'clean', tasks: [sampleTask]),
  }, defaultTasks: {
    sampleTask,
  });
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

String _basicPubSpec(String name) => '''
name: ${name.replaceAll('-', '_')}
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
    await _createNewDartProject();
  } else {
    await _createNewBasicProject(pubspecFile);
  }
  logger.fine('Installing new project\'s dependencies');
  final code = await exec(Process.start('dart', const ['pub', 'get']));
  if (code != 0) {
    throw DartleException(
        message: '"dart pub get" program failed with code $code');
  }
}

Future<void> _createNewBasicProject(File pubspecFile) async {
  logger.fine('Creating basic Dartle Project.');
  await pubspecFile.writeAsString(
      _basicPubSpec(p.basename(Directory.current.path)),
      flush: true);
  await File('dartle.dart').writeAsString(_basicDartleFile, flush: true);
  await Directory('dartle-src').create();
  await File(p.join('dartle-src', 'tasks.dart'))
      .writeAsString(_basicTaskFile, flush: true);
  await Directory('source').create();
  await File(p.join('source', 'input.txt'))
      .writeAsString(_basicInputFile, flush: true);
}

Future<void> _createNewDartProject() async {
  logger.fine(
      'pubspec already exists, creating Dartle Project with Dart support');
  await File('dartle.dart').writeAsString(_dartDartleFile, flush: true);

  // don't worry if this errors, it means the pubspec probably already
  // had dartle as a dependency
  await exec(Process.start('dart', const ['pub', 'add', '--dev', 'dartle']));
}
