import 'dart:convert';

import 'package:dartle/dartle.dart';

final allTasks = [
  Task(hello, argsValidator: const ArgsCount.range(min: 0, max: 1)),
  Task(bye, dependsOn: const {'hello'}),
  Task(clean),
  Task(encodeBase64,
      description: 'Encodes input.txt in base64, writing to output.txt',
      runCondition: RunOnChanges(
        inputs: file('input.txt'),
        outputs: file('output.txt'),
      )),
];

void main(List<String> args) async =>
    run(args, tasks: allTasks.toSet(), defaultTasks: {allTasks[0]});

/// To pass an argument to a task, use a ':' prefix, e.g.:
/// dartle hello :joe
void hello(List<String> args) =>
    print("Hello ${args.isEmpty ? 'World' : args[0]}!");

/// If no arguments are expected, use `_` as the function parameter.
void bye(_) => print('Bye!');

Future<void> encodeBase64(_) async {
  final input = await (await file('input.txt').files.first).readAsBytes();
  await (await file('output.txt').files.first)
      .writeAsString(base64.encode(input));
}

Future<void> clean(_) => deleteOutputs(allTasks);
