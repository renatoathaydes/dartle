import 'package:dartle/dartle.dart';
import 'package:test/test.dart';

void noop(_) {}

final _a = Task(noop, name: 'a', dependsOn: {'b', 'c'});
final _b = Task(noop, name: 'b');
final _c = Task(noop, name: 'c');
final _d = Task(noop, name: 'd', dependsOn: {'a'});

// TaskWithDeps includes transitive dependencies
final _aw = TaskWithDeps(_a, [_bw, _cw]);
final _bw = TaskWithDeps(_b);
final _cw = TaskWithDeps(_c);
final _dw = TaskWithDeps(_d, [_bw, _cw, _aw]);

void main() {
  group('TaskWithDeps', () {
    test('can be created from simple tasks', () {
      var taskMap = createTaskMap([_a, _b, _c]);
      expect(taskMap, equals({'a': _aw, 'b': _bw, 'c': _cw}));

      taskMap = createTaskMap([_a, _b, _c, _d]);
      expect(taskMap, equals({'a': _aw, 'b': _bw, 'c': _cw, 'd': _dw}));
    });

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

    test('detects direct dependency cycles', () {
      final e = Task(noop, name: 'e', dependsOn: {'f'});
      final f = Task(noop, name: 'f', dependsOn: {'e'});

      expect(
          () => createTaskMap([e, f]),
          throwsA(isA<DartleException>().having(
              (e) => e.message,
              'error message',
              equals('Task dependency cycle detected: [e -> f -> e]'))));
    });

    test('detects indirect dependency cycles', () {
      final e = Task(noop, name: 'e', dependsOn: {'f'});
      final f = Task(noop, name: 'f', dependsOn: {'g'});
      final g = Task(noop, name: 'g', dependsOn: {'h'});
      final h = Task(noop, name: 'h', dependsOn: {'e'});

      expect(
          () => createTaskMap([e, g, h, f]),
          throwsA(isA<DartleException>().having(
              (e) => e.message,
              'error message',
              equals('Task dependency cycle detected: '
                  '[e -> f -> g -> h -> e]'))));
    });

    test('cannot depend on non-declared dependency', () {
      var task = Task(noop, name: 't', dependsOn: {'g'});

      expect(
          () => createTaskMap([task]),
          throwsA(isA<DartleException>().having(
              (e) => e.message,
              'error message',
              equals("Task with name 'g' does not exist "
                  '(dependency path: [t -> g])'))));
    });
  });

  group('Tasks', () {
    test('can run in order of their dependencies', () async {
      var tasksInOrder = await getInOrderOfExecution(
          [_aw].map((t) => TaskInvocation(t)).toList());
      expect(
          tasksInOrder.map((t) => t.invocations.map((i) => i.task.name)),
          equals([
            ['b', 'c'],
            ['a']
          ]));

      tasksInOrder = await getInOrderOfExecution(
          [_aw, _bw, _cw, _dw].map((t) => TaskInvocation(t)).toList());
      expect(
          tasksInOrder.map((t) => t.invocations.map((i) => i.task.name)),
          equals([
            ['b', 'c'],
            ['a'],
            ['d']
          ]));

      tasksInOrder = await getInOrderOfExecution(
          [_dw].map((t) => TaskInvocation(t)).toList());
      expect(
          tasksInOrder.map((t) => t.invocations.map((i) => i.task.name)),
          equals([
            ['b', 'c'],
            ['a'],
            ['d']
          ]));
    });

    test('maintains provided order if no dependency between tasks', () async {
      var tasksInOrder = await getInOrderOfExecution(
          [_cw, _bw, _aw].map((t) => TaskInvocation(t)).toList());
      expect(
          tasksInOrder.map((t) => t.invocations.map((i) => i.task.name)),
          equals([
            ['c', 'b'],
            ['a']
          ]));

      tasksInOrder = await getInOrderOfExecution(
          [_aw, _cw, _bw, _dw].map((t) => TaskInvocation(t)).toList());
      expect(
          tasksInOrder.map((t) => t.invocations.map((i) => i.task.name)),
          equals([
            ['c', 'b'],
            ['a'],
            ['d']
          ]));
    });
  });
}
