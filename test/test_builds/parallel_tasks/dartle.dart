import 'package:dartle/dartle.dart';
import 'package:dartle/src/_log.dart';

final env = <String>{};

final allTasks = {
  Task(sayHi),
  Task(sayArgs),
  Task(sayHo),
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

void showEnv(_) => print('Env=$env');
