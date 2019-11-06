import 'package:dartle/dartle.dart';
import 'package:dartle/dartle_cache.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'io_test.dart';
import 'test_utils.dart';

void main() {
  group('RunOnChanges', () {
    test('never runs if inputs/outputs are empty', () async {
      final ins = FileCollection.empty;
      final outs = FileCollection.empty;
      final runOnChanges = RunOnChanges(inputs: ins, outputs: outs);
      expect(await runOnChanges.shouldRun(), isFalse);
    });

    test('runs if any inputs change', () async {
      final cache = _TestCache();
      final ins = file('a');
      final outs = FileCollection.empty;
      when(cache.hasChanged(ins)).thenAnswer((_) => Future.value(true));
      when(cache.hasChanged(outs)).thenAnswer((_) => Future.value(false));

      final runOnChanges =
          RunOnChanges(inputs: ins, outputs: outs, cache: cache);

      expect(await runOnChanges.shouldRun(), isTrue);
    });

    test('runs if any outpus change', () async {
      final cache = _TestCache();
      final ins = FileCollection.empty;
      final outs = files(['a', 'b', 'c']);
      when(cache.hasChanged(ins)).thenAnswer((_) => Future.value(false));
      when(cache.hasChanged(outs)).thenAnswer((_) => Future.value(true));

      final runOnChanges =
          RunOnChanges(inputs: ins, outputs: outs, cache: cache);

      expect(await runOnChanges.shouldRun(), isTrue);
    });

    test('runs if both intpus and outpus change', () async {
      final cache = _TestCache();
      final ins = file('z');
      final outs = files(['a', 'b', 'c']);
      when(cache.hasChanged(ins)).thenAnswer((_) => Future.value(true));
      when(cache.hasChanged(outs)).thenAnswer((_) => Future.value(true));

      final runOnChanges =
          RunOnChanges(inputs: ins, outputs: outs, cache: cache);

      expect(await runOnChanges.shouldRun(), isTrue);
    });

    test('does not run if no inputs or outpus change', () async {
      // should not run as the outputs already exist and are not modified
      final fs =
          await createFileSystem(['a', 'b', 'c'].map((f) => Entry.file(f)));

      var wouldRun = await withFileSystem(fs, () async {
        final cache = _TestCache();
        final ins = file('z');
        final outs = files(['a', 'b', 'c']);
        when(cache.hasChanged(ins)).thenAnswer((_) => Future.value(false));
        when(cache.hasChanged(outs)).thenAnswer((_) => Future.value(false));

        final runOnChanges =
            RunOnChanges(inputs: ins, outputs: outs, cache: cache);

        return await runOnChanges.shouldRun();
      });
      expect(wouldRun, isFalse);
    });

    test('runs if inputs and outpus did not change but output does not exist',
        () async {
      final fs = await createFileSystem([]);

      var wouldRun = await withFileSystem(fs, () async {
        final cache = _TestCache();
        final ins = file('in');
        final outs = files(['out']);
        when(cache.hasChanged(ins)).thenAnswer((_) => Future.value(false));
        when(cache.hasChanged(outs)).thenAnswer((_) => Future.value(false));

        final runOnChanges =
            RunOnChanges(inputs: ins, outputs: outs, cache: cache);

        return await runOnChanges.shouldRun();
      });
      expect(wouldRun, isTrue);
    });
  });
}

class _TestCache extends Mock implements DartleCache {}
