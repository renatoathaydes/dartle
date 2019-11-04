import 'task.dart';

class TaskWithDeps implements Task, Comparable<TaskWithDeps> {
  final Task _task;
  final List<TaskWithDeps> dependencies;

  TaskWithDeps(this._task, [this.dependencies = const []]);

  String get name => _task.name;

  get action => _task.action;

  Set<String> get dependsOn => dependencies.map((t) => t.name).toSet();

  String get description => _task.description;

  RunCondition get runCondition => _task.runCondition;

  @override
  String toString() {
    return 'TaskWithDeps{task: $_task, dependencies: $dependsOn}';
  }

  @override
  int compareTo(TaskWithDeps other) {
    const thisBeforeOther = -1;
    const thisAfterOther = 1;
    if (this.dependsOn.contains(other.name)) return thisAfterOther;
    if (other.dependsOn.contains(this.name)) return thisBeforeOther;
    return 0;
  }
}
