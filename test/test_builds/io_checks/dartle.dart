import 'dart:convert';
import 'dart:io';

import 'package:dartle/dartle.dart';
import 'package:path/path.dart' as path;

final inputs = dir('inputs', fileExtensions: const {'txt'});
final outputs = dir('outputs', fileExtensions: const {'b64.txt'});

final allTasks = {
  Task(base64, runCondition: RunOnChanges(inputs: inputs, outputs: outputs)),
};

void main(List<String> args) async => await run(args, tasks: allTasks);

Future base64(_) async {
  final inputDir = inputs.directories.first.path;
  final outDir = outputs.directories.first.path;
  await for (final file in inputs.resolveFiles()) {
    final filePath = file.path.substring(inputDir.length + 1);
    print('b64 encoding file $filePath');
    final outputPath = '${path.withoutExtension(filePath)}.b64.txt';
    final encoded = base64Encode(await file.readAsBytes());
    final outputFile = File(path.join(outDir, outputPath));
    await outputFile.parent.create(recursive: true);
    await outputFile.writeAsString(encoded, encoding: ascii);
  }
}
