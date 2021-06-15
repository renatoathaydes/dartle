import 'dart:async';

import 'package:dartle/dartle.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

final _invocation = taskInvocation('name');

void main() {
  group('AndCondition', () {
    test('runs only if all of its conditions run', () async {
      expect(
          await AndCondition(const [AlwaysRun(), AlwaysRun()])
              .shouldRun(_invocation),
          isTrue);
      expect(
          await AndCondition(const [AlwaysRun(), _NeverRuns()])
              .shouldRun(_invocation),
          isFalse);
      expect(
          await AndCondition(const [_NeverRuns(), AlwaysRun()])
              .shouldRun(_invocation),
          isFalse);
      expect(
          await AndCondition(const [_NeverRuns(), _NeverRuns()])
              .shouldRun(_invocation),
          isFalse);
    });
  });
  group('OrCondition', () {
    test('runs if any of its conditions runs', () async {
      expect(
          await OrCondition(const [AlwaysRun(), AlwaysRun()])
              .shouldRun(_invocation),
          isTrue);
      expect(
          await OrCondition(const [AlwaysRun(), _NeverRuns()])
              .shouldRun(_invocation),
          isTrue);
      expect(
          await OrCondition(const [_NeverRuns(), AlwaysRun()])
              .shouldRun(_invocation),
          isTrue);
      expect(
          await OrCondition(const [_NeverRuns(), _NeverRuns()])
              .shouldRun(_invocation),
          isFalse);
    });
  });
}

class _NeverRuns with RunCondition {
  const _NeverRuns();

  @override
  FutureOr<void> postRun(TaskResult result) {}

  @override
  FutureOr<bool> shouldRun(TaskInvocation invocation) async {
    return false;
  }
}
