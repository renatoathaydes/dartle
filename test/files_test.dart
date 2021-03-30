import 'package:file/memory.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

void main([List<String> args = const []]) {
  group('MemoryFileSystem', () {
    var fs = MemoryFileSystem();

    setUp(() async {
      fs = MemoryFileSystem();
    });

    test('can list files inside a directory', () async {
      final dir = fs.directory('d');
      await dir.create();
      final foo = fs.file(join('d', 'foo'));
      await foo.writeAsString('foo', flush: true);
      final bar = fs.file(join('d', 'bar'));
      await bar.writeAsString('bar', flush: true);
      expect(dir.list().map((f) => f.basename),
          emitsInAnyOrder(['foo', 'bar', emitsDone]));
    });
  });
}
