import 'package:dartle/dartle.dart';

final allTasks = [Task(hello), Task(bye)];

main(List<String> args) async =>
    run(args, tasks: allTasks, defaultTasks: allTasks.sublist(0, 1));

hello() async {
  print("Hello!");
}

bye() async {
  print("Bye!");
}
