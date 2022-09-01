import 'dart:convert';

import 'dart:io';
import 'package:dartle/dartle.dart';
import 'package:path/path.dart' as p;

/// Use Dartle's FileCollection factory methods (file, files, dir, dirs)
/// to manage task's inputs/outputs.
final outDir = 'out';

FileCollection base64Inputs =
    dir('.', fileExtensions: const {'txt'}, recurse: false);

FileCollection base64Outputs =
    dir(outDir, fileExtensions: const {'txt'}, recurse: false);

/// Task declarations.

final _hello =
    Task(hello, argsValidator: const ArgsCount.range(min: 0, max: 1));
final _bye = Task(bye, dependsOn: const {'hello'});
final _encodeBase64 = Task(encodeBase64,
    description: 'Encodes input.txt in base64, writing to output.txt',
    runCondition: RunOnChanges(
      inputs: base64Inputs,
      outputs: base64Outputs,
    ));

final mainTasks = [_hello, _bye, _encodeBase64];

// most builds can benefit from a standard 'clean' task that simply
// deletes the outputs of all tasks when invoked.
final _clean = createCleanTask(
    name: 'clean',
    tasks: mainTasks,
    description: 'Deletes all outputs of this build.');

/// main - always delegate to Dartle's `run` function to execute a build
void main(List<String> args) async =>
    run(args, tasks: {...mainTasks, _clean}, defaultTasks: {_hello});

/////////////////////////////////////////////////////////////////////

// Task actions. On larger projects, it's a good idea to move these
// to their own files, under "dartle-src" by convention.

/////////////////////////////////////////////////////////////////////

/// To pass an argument to a task, use a ':' prefix, e.g.:
/// dartle hello :joe
void hello(List<String> args) =>
    print("Hello ${args.isEmpty ? 'World' : args[0]}!");

/// If no arguments are expected, use `_` as the function parameter.
void bye(_) => print('Bye!');

Future<void> encodeBase64(_) async {
  final inputs = base64Inputs.resolveFiles();
  await for (final input in inputs) {
    final encoded = base64.encode(await input.readAsBytes());
    await Directory(outDir).create(recursive: true);
    final output = p.join(outDir, p.setExtension(input.path, 'b64.txt'));
    await File(output).writeAsString(encoded);
  }
}
