import 'package:dartle/dartle.dart';
import 'package:dartle/src/_task.dart';
import 'package:test/test.dart';

void noop() {}

final _a = Task(noop, name: 'a', dependsOn: {'b', 'c'});
final _b = Task(noop, name: 'b');
final _c = Task(noop, name: 'c');
final _d = Task(noop, name: 'd', dependsOn: {'a'});

// TaskWithDeps includes transitive dependencies
final _aw = TaskWithDeps(_a, {_bw, _cw});
final _bw = TaskWithDeps(_b);
final _cw = TaskWithDeps(_c);
final _dw = TaskWithDeps(_d, {_aw, _bw, _cw});

void main() {
  group('TaskWithDeps', () {
    test('sorts correctly', () {
      var tasks = [_dw, _bw, _aw];
      tasks.sort();
      expect(tasks.map((t) => t.name), orderedEquals(['b', 'a', 'd']));

      tasks = [_aw, _dw, _bw];
      tasks.sort();
      expect(tasks.map((t) => t.name), orderedEquals(['b', 'a', 'd']));

      tasks = [_bw, _aw];
      tasks.sort();
      expect(tasks.map((t) => t.name), orderedEquals(['b', 'a']));

      tasks = [_cw, _aw];
      tasks.sort();
      expect(tasks.map((t) => t.name), orderedEquals(['c', 'a']));
    });
  });

  group('Tasks', () {
    test('can run in order of their dependencies', () async {
      final tasksInOrder = expandToOrderOfExecution([_aw]);
      expect(tasksInOrder.map((t) => t.name), orderedEquals(['b', 'c', 'a']));
    });
  });
}
