import 'package:dartle/dartle.dart';

import 'dartle-src/tasks.dart';

void main(List<String> args) {
  run(
    args,
    tasks: {
      createOutputTask,
      countOutputTask,
      createCleanTask(
        name: 'clean',
        tasks: [createOutputTask, countOutputTask],
      ),
    },
    defaultTasks: {createOutputTask},
  );
}
