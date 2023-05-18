import 'dart:io';

import 'package:path/path.dart' as p;

import '_log.dart';
import '_utils.dart';
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

final sources = dir('source');
const target = 'target';

/// The task name is the name of the function given to it, unless overridden.
final sampleTask = Task(sample,
    description: 'Sample Task',
    // This task will only run if the inputs/outputs changed
    // since the last time it ran
    runCondition: RunOnChanges(inputs: sources, outputs: dir(target)));

Future<void> sample(_) async {
  final inputFiles = await sources.resolveFiles().toList();
  await Directory(target, recursive: true).create();
  await File('$target/output.txt').writeAsString(
      inputFiles.map((e) => '${e.path}: ${e.statSync().size}').join('\n'));
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
description: Build script for this project. Check Dartle Documentation at https://renatoathaydes.github.io/dartle-website/.
version: 0.0.0
publish_to: none

environment:
  sdk: ^${Platform.version.split(' ').first}

dev_dependencies:
  dartle: ^$dartleVersion
''';

Never abort(int code) {
  exit(code);
}

Future<void> onNoPubSpec(bool doNotExit) async {
  stdout.write('There is no pubspec.yaml file in the current directory.\n'
      'Would you like to create one [y/N]? ');
  final answer = stdin.readLineSync()?.toLowerCase();
  if (answer == 'y' || answer == 'yes') {
    await _createPubSpec();
  } else if (doNotExit) {
    throw DartleException(message: 'Missing pubspec.yaml', exitCode: 4);
  } else {
    logger.severe(dartleFileMissingMessage);
    abort(4);
  }
}

Future<void> onNoDartleFile(bool doNotExit) async {
  stdout.write('There is no dartle.dart file in the current directory.\n'
      'Would you like to create one [y/N]? ');
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
  final pubspecFile = File(pubspec);
  if (await pubspecFile.exists()) {
    await _createNewDartProject();
  } else {
    await _createNewBasicProject();
  }
}

Future<void> _createNewBasicProject() async {
  logger.fine('Creating basic Dartle Project.');
  await _createPubSpec();
  await File('dartle.dart').writeAsString(_basicDartleFile, flush: true);
  await Directory('dartle-src').create();
  await File(p.join('dartle-src', 'tasks.dart'))
      .writeAsString(_basicTaskFile, flush: true);
  await Directory('source').create();
  await File(p.join('source', 'input.txt'))
      .writeAsString(_basicInputFile, flush: true);
}

Future<void> _createPubSpec() async {
  await File(pubspec).writeAsString(
      _basicPubSpec(p.basename(Directory.current.path)),
      flush: true);
}

Future<void> _createNewDartProject() async {
  logger.fine(
      'pubspec already exists, creating Dartle Project with Dart support');
  await File('dartle.dart').writeAsString(_dartDartleFile, flush: true);

  // don't worry if this errors, it means the pubspec probably already
  // had dartle as a dependency
  await exec(Process.start('dart', const ['pub', 'add', '--dev', 'dartle']));
}
