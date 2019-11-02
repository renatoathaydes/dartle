import 'package:dartle/dartle.dart';
import 'package:dartle/dartle_cache.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

void main() {
  group('RunOnChanges', () {
    test('never runs if inputs/outputs are empty', () async {
      final ins = FileCollection.empty();
      final outs = FileCollection.empty();
      final runOnChanges = RunOnChanges(inputs: ins, outputs: outs);
      expect(await runOnChanges.shouldRun(), isFalse);
    });

    test('runs if any inputs change', () async {
      final cache = _TestCache();
      final ins = FileCollection.file('a');
      final outs = FileCollection.empty();
      when(cache.hasChanged(ins)).thenAnswer((_) => Future.value(true));
      when(cache.hasChanged(outs)).thenAnswer((_) => Future.value(false));

      final runOnChanges =
          RunOnChanges(inputs: ins, outputs: outs, cache: cache);

      expect(await runOnChanges.shouldRun(), isTrue);
    });

    test('runs if any outpus change', () async {
      final cache = _TestCache();
      final ins = FileCollection.empty();
      final outs = FileCollection.files(['a', 'b', 'c']);
      when(cache.hasChanged(ins)).thenAnswer((_) => Future.value(false));
      when(cache.hasChanged(outs)).thenAnswer((_) => Future.value(true));

      final runOnChanges =
          RunOnChanges(inputs: ins, outputs: outs, cache: cache);

      expect(await runOnChanges.shouldRun(), isTrue);
    });

    test('runs if both intpus and outpus change', () async {
      final cache = _TestCache();
      final ins = FileCollection.file('z');
      final outs = FileCollection.files(['a', 'b', 'c']);
      when(cache.hasChanged(ins)).thenAnswer((_) => Future.value(true));
      when(cache.hasChanged(outs)).thenAnswer((_) => Future.value(true));

      final runOnChanges =
          RunOnChanges(inputs: ins, outputs: outs, cache: cache);

      expect(await runOnChanges.shouldRun(), isTrue);
    });

    test('does not run if no intpus nor outpus change', () async {
      final cache = _TestCache();
      final ins = FileCollection.file('z');
      final outs = FileCollection.files(['a', 'b', 'c']);
      when(cache.hasChanged(ins)).thenAnswer((_) => Future.value(false));
      when(cache.hasChanged(outs)).thenAnswer((_) => Future.value(false));

      final runOnChanges =
          RunOnChanges(inputs: ins, outputs: outs, cache: cache);

      expect(await runOnChanges.shouldRun(), isFalse);
    });
  });
}

class _TestCache extends Mock implements DartleCache {}
