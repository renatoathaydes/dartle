import 'dart:io';

import 'package:dartle/dartle.dart';
import 'package:path/path.dart' as p;

final sources = dir('source');
const target = 'target';
final outputFile = p.join(target, 'output.txt');
final bytesFile = p.join(target, 'bytes.txt');

final createOutputTask = Task(
  createOutput,
  description: 'Creates an output file',
  phase: TaskPhase.build,
  runCondition: RunOnChanges(inputs: sources, outputs: file(outputFile)),
);

final countOutputTask = Task(
  countTotalBytes,
  description: 'Counts how many lines the output file has',
  dependsOn: {'createOutput'},
  phase: TaskPhase.tearDown,
  runCondition: RunOnChanges(
    inputs: file(outputFile),
    outputs: file(bytesFile),
  ),
);

Future<void> createOutput(_) async {
  final inputFiles = await sources.resolveFiles().toList();
  await Directory(target).create(recursive: true);
  await File(outputFile).writeAsString(
    inputFiles.map((e) => '${e.path}: ${e.statSync().size}').join('\n'),
  );
}

Future<void> countTotalBytes(_) async {
  final lines = await File(outputFile).readAsLines();
  final totalBytes = lines
      .map((line) {
        final colIndex = line.lastIndexOf(': ');
        if (colIndex > 0) {
          return int.parse(line.substring(colIndex + 2));
        }
        return 0;
      })
      .fold(0, (a, b) => a + b);
  await File(bytesFile).writeAsString('$totalBytes');
}
