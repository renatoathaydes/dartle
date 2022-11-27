import 'package:dartle/dartle.dart';
import 'package:test/test.dart';

import 'cache_mock.dart';
import 'file_collection_test.dart';
import 'test_utils.dart';

final _invocation = taskInvocation('name');

void main() {
  group('RunOnChanges', () {
    var cache = CacheMock();
    setUp(() {
      cache = CacheMock()
        ..invocationChanges = {
          _invocation.name: [false, false]
        };
    });

    test('never runs if inputs/outputs are empty', () async {
      final ins = FileCollection.empty;
      final outs = FileCollection.empty;
      cache.hasChangedInvocations[ins] = false;
      cache.hasChangedInvocations[outs] = false;

      final runOnChanges =
          RunOnChanges(inputs: ins, outputs: outs, cache: cache);
      expect(await runOnChanges.shouldRun(_invocation), isFalse);
    });

    test('runs if any inputs change', () async {
      final ins = file('a');
      final outs = FileCollection.empty;
      cache.hasChangedInvocations[ins] = true;
      cache.hasChangedInvocations[outs] = false;

      final runOnChanges =
          RunOnChanges(inputs: ins, outputs: outs, cache: cache);

      expect(await runOnChanges.shouldRun(_invocation), isTrue);
    });

    test('runs if any outpus change', () async {
      final ins = FileCollection.empty;
      final outs = files(['a', 'b', 'c']);
      cache.hasChangedInvocations[ins] = false;
      cache.hasChangedInvocations[outs] = true;

      final runOnChanges =
          RunOnChanges(inputs: ins, outputs: outs, cache: cache);

      expect(await runOnChanges.shouldRun(_invocation), isTrue);
    });

    test('runs if both intpus and outpus change', () async {
      final ins = file('z');
      final outs = files(['a', 'b', 'c']);
      cache.hasChangedInvocations[ins] = true;
      cache.hasChangedInvocations[outs] = true;

      final runOnChanges =
          RunOnChanges(inputs: ins, outputs: outs, cache: cache);

      expect(await runOnChanges.shouldRun(_invocation), isTrue);
    });

    test('does not run if no inputs or outputs change', () async {
      // should not run as the outputs already exist and are not modified
      final fs =
          await createFileSystem(['a', 'b', 'c'].map((f) => Entry.file(f)));

      var wouldRun = await withFileSystem(fs, () async {
        final ins = file('z');
        final outs = files(['a', 'b', 'c']);
        cache.hasChangedInvocations[ins] = false;
        cache.hasChangedInvocations[outs] = false;

        final runOnChanges =
            RunOnChanges(inputs: ins, outputs: outs, cache: cache);

        return await runOnChanges.shouldRun(_invocation);
      });
      expect(wouldRun, isFalse);
    });

    test(
        'does not run if inputs and outputs did not change but output does not exist',
        () async {
      final fs = await createFileSystem([]);

      var wouldRun = await withFileSystem(fs, () async {
        final ins = file('in');
        final outs = files(['out']);
        cache.hasChangedInvocations[ins] = false;
        cache.hasChangedInvocations[outs] = false;

        final runOnChanges =
            RunOnChanges(inputs: ins, outputs: outs, cache: cache);

        return await runOnChanges.shouldRun(_invocation);
      });
      expect(wouldRun, isFalse);
    });
  });
}
