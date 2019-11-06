import 'dart:io';

import 'package:dartle/dartle.dart';
import 'package:path/path.dart' show extension;

final libDir = dir('lib', fileFilter: (f) => extension(f.path) == '.dart');

final testTask = Task(test,
    description: 'Runs all tests',
    runCondition:
        RunOnChanges(inputs: dirs(const ['lib', 'bin', 'test', 'example'])));

final checkImportsTask = Task(checkImports,
    description: 'Checks dart file imports are allowed',
    runCondition: RunOnChanges(inputs: libDir));

void main(List<String> args) =>
    run(args, tasks: {testTask, checkImportsTask}, defaultTasks: {testTask});

test() async {
  final stdoutConsumer = StdStreamConsumer(keepLines: true);
  final code = await exec(
      Process.start('pub', const ['run', 'test', '-p', 'vm']),
      name: 'Dart Tests',
      onStdoutLine: stdoutConsumer);
  if (code != 0) {
    stdoutConsumer.lines.forEach(print);
    failBuild(reason: 'Tests failed');
  }
}

checkImports() async {
  await for (final file in libDir.files) {
    final illegalImports = (await file.readAsLines()).where(
        (line) => line.contains(RegExp("^import\\s+['\"]package:dartle")));
    if (illegalImports.isNotEmpty) {
      throw DartleException(
          message: 'File ${file.path} contains '
              'self import to the dartle package: ${illegalImports}');
    }
  }
}
