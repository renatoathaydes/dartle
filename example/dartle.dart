import 'dart:convert';
import 'dart:io';

import 'package:dartle/dartle.dart';

final allTasks = [
  Task(hello),
  Task(bye),
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

hello([_]) => print("Hello!");

bye([_]) => print("Bye!");

/// To pass an argument to a task, e.g. "sleep" for this task, run as in
/// 'dartle sleep -Dsleep=10'.
sleep([_]) async => await Future.delayed(
    Duration(seconds: int.fromEnvironment('sleep', defaultValue: 2)));

encodeBase64([_]) async {
  final input = await File('input.txt').readAsBytes();
  await File('output.txt').writeAsString(base64.encode(input));
}

clean([_]) => deleteOutputs(allTasks);
