import 'package:dartle/dartle.dart';

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

Future sayHi(_) => _withEnv('hi', () => print('Hi'));

Future sayHo(_) => _withEnv('ho', () => print('Ho'));

Future sayArgs([List<String>? args]) => _withEnv('args', () => print(args));

void showEnv(_) => print('Env=$env');
