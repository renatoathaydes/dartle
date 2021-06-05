import 'dart:io';

import 'package:dartle/dartle_cache.dart';
import 'package:path/path.dart' as p;

import '_log.dart';
import 'exec.dart';
import 'file_collection.dart';
import 'run_condition.dart';
import 'task.dart';

///
/// The Windows implementation requires that we compile to a temporary file,
/// and only replace the exe file AFTER the current process has ended.
/// We achieve that by running a detached Dart process whose job is to replace
/// the exe file with the newly compiled file as soon as it can, which should
/// be as soon as this process dies.
///
Future<TaskWithDeps> createDartCompileTaskWin(
    File dartlex, File tmpDartlex) async {
  final buildFile = File('dartle.dart').absolute;
  final buildSetupFiles = [buildFile.path, 'pubspec.yaml', 'pubspec.lock'];

  // no outputs because the tempFile is created but then deleted
  final runCompileCondition = RunOnChanges(
    inputs: files(buildSetupFiles),
  );

  return TaskWithDeps(Task((_) async {
    await createDartExe(buildFile, tmpDartlex);
    await scheduleReplaceScript(dartlex, tmpDartlex);
  },
      name: '_compileDartleFile',
      runCondition: runCompileCondition,
      description: 'Internal task that compiles the Dartle project\'s '
          'build file into an executable for better performance'));
}

Future<void> scheduleReplaceScript(File dartlex, File tmpDartlex) async {
  final replaceScript =
      File(p.join(Directory.systemTemp.path, 'replace-dartlex-$pid'));
  await replaceScript.writeAsString(_replaceScript(dartlex, tmpDartlex),
      flush: true);
  final proc = await Process.start('dart', [replaceScript.absolute.path],
      mode: ProcessStartMode.detached);
  logger.fine('Started dartlex replace script with PID=${proc.pid}');
}

String _replaceScript(File dartlex, File tmpDartlex) => '''
import 'dart:io';

void main() async {
  final dartlex = File('${dartlex.absolute.path}');
  final tmpDartlex = File('${tmpDartlex.absolute.path}');
'''
    r'''
  while (true) {
    try {
      await tmpDartlex.rename(dartlex.path);
      break;
    } catch (e) {
      await Future.delayed(Duration(seconds: 1));
    }
  }
}
''';
