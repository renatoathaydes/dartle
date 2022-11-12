import 'dart:io';

import 'package:dartle/dartle.dart';
import 'package:dartle/src/_log.dart';

final env = <String>{};

final allTasks = {
  Task(sayHi),
  Task(sayArgs),
  Task(sayHo),
  Task(throwError),
  Task(delayedMessage),
  Task(showEnv, dependsOn: {'sayHi', 'sayArgs', 'sayHo'}),
};

void main(List<String> args) async => await run(args, tasks: allTasks);

Future _withEnv(String envValue, Function() action) async {
  env.add(envValue);
  await action();
}

Future sayHi(_) => _withEnv('hi', () => logger.info('Hi'));

Future sayHo(_) => _withEnv('ho', () => logger.info('Ho'));

Future sayArgs([List<String>? args]) =>
    _withEnv('args', () => logger.info(args));

Future delayedMessage(_) => Future.delayed(const Duration(seconds: 1))
    .then((_) => logger.warning('Managed to log delayed message'));

Future throwError(_) async {
  await _readNonExistingFile();
}

Future _readNonExistingFile() async {
  final s = await File('does_not_exist').readAsString();
  print('The file existed!! Contents: $s');
}

void showEnv(_) => print('Env=$env');
