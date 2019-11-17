import 'dart:convert';
import 'dart:io';

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

main(List<String> args) async =>
    run(args, tasks: allTasks.toSet(), defaultTasks: {allTasks[0]});

/// To pass an argument to a task, use a ':' prefix, e.g.:
/// dartle hello :joe
hello([List<String> args = const []]) =>
    print("Hello ${args.isEmpty ? 'World' : args[0]}!");

/// If no arguments are expected, use `[_]` as the function parameter.
bye([_]) => print("Bye!");

encodeBase64([_]) async {
  final input = await File('input.txt').readAsBytes();
  await File('output.txt').writeAsString(base64.encode(input));
}

clean([_]) => deleteOutputs(allTasks);
