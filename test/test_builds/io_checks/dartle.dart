import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartle/dartle.dart';
import 'package:dartle/src/cache/cache.dart';
import 'package:path/path.dart' as path;

final inputs = dir('inputs', fileExtensions: const {'txt'});
final outputs = dir('outputs', fileExtensions: const {'b64.txt'});

final incInputs = dir('inc-inputs', fileExtensions: const {'txt'});
final incOutputs = dir('inc-outputs', fileExtensions: const {'txt'});

final allTasks = {
  Task(base64, runCondition: RunOnChanges(inputs: inputs, outputs: outputs)),
  Task(ExampleIncrementalAction(),
      name: 'incremental',
      runCondition: RunOnChanges(inputs: incInputs, outputs: incOutputs)),
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

class ExampleIncrementalAction {
  Future<void> call(List<String> _,
      [List<FileChange> changes = const []]) async {
    print(
        'Changes : ${changes.map((c) => '${c.kind.name}: ${c.entity.path}\n')}');
    final inputDir = Directory(incInputs.directories.first.path);
    if (!await inputDir.exists()) {
      return;
    }
    final outDir = Directory(incOutputs.directories.first.path);
    await outDir.create();
    final output = File(path.join(outDir.path, 'out.txt'));

    List<String> toWrite;

    if (changes.isEmpty) {
      toWrite = ['first run'];
    } else {
      toWrite = changes.map((c) => '${c.kind.name}: ${c.entity.path}').toList();
    }

    toWrite.sort();
    final handle = await output.open(mode: FileMode.writeOnly);
    try {
      await handle.writeString(toWrite.join('\n'));
    } finally {
      handle.close();
    }
  }
}
