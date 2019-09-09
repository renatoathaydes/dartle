import 'dart:convert';
import 'dart:io';

import 'package:dartle/dartle.dart';
import 'package:dartle/src/io.dart';

final allTasks = [
  Task(hello),
  Task(bye),
  Task(encodeBase64,
      description: 'Encodes input.txt in base64, writing to output.txt',
      runCondition: FilesRunCondition(
          inputs: FileCollection.file(File('input.txt')),
          outputs: FileCollection.file(File('output.txt')))),
];

main(List<String> args) async =>
    run(args, tasks: allTasks, defaultTasks: [allTasks[0]]);

hello() {
  print("Hello!");
}

bye() {
  print("Bye!");
}

encodeBase64() async {
  final input = await File('input.txt').readAsBytes();
  await File('output.txt').writeAsString(base64.encode(input));
}
