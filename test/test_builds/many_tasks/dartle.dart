import 'package:dartle/dartle.dart';

void noop(_) {}

final tasks = [
  Task(noop, name: 'a', description: 'Task A', dependsOn: {'b', 'c'}),
  Task(noop, name: 'b', description: 'Task B', dependsOn: {'f'}),
  Task(noop, name: 'c', dependsOn: {'d', 'e', 'm'}),
  Task(noop, name: 'd'),
  Task(noop, name: 'e'),
  Task(noop, name: 'f', dependsOn: {'g', 'n'}),
  Task(noop, name: 'g', dependsOn: {'c'}),
  Task(noop, name: 'h', phase: TaskPhase.tearDown),
  Task(noop, name: 'i', dependsOn: {'d'}),
  Task(noop, name: 'j'),
  Task(noop, name: 'k', dependsOn: {'a'}),
  Task(noop, name: 'l', argsValidator: const AcceptAnyArgs()),
  Task(noop, name: 'm', runCondition: RunAtMostEvery(Duration(seconds: 4))),
  Task(noop, name: 'n'),
  Task(noop, name: 'o', description: 'Task O'),
];

void main(List<String> args) =>
    run(args, tasks: tasks.toSet(), defaultTasks: tasks.sublist(0, 3).toSet());
