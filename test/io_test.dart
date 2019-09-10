import 'package:dartle/dartle.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('FilesCollection', () {
    FileSystem fs;

    setUpAll(() async {
      fs = await createFileSystem([
        Entry.fileWithText('dartle.dart', 'hello world'),
        ...['dartle', 'a', 'b', 'c', 'd', 'e'].map((d) => Entry.directory(d))
      ]);
    });
    test('can be created for a single file', () async {
      final files = FileCollection.file('dartle.dart');
      expectFiles(files, files: ['dartle.dart']);
      await expectEmpty(files.directories);
    });
    test('can be created for multiple files', () async {
      final files = FileCollection.files(const ['a', 'b', 'c', 'd', 'e']);
      expectFiles(files, files: const ['a', 'b', 'c', 'd', 'e']);
      await expectEmpty(files.directories);
    });

    // FileCollections containing directories require them to exist
    test('can be created for a single directory', () async {
      await withFileSystem(fs, () async {
        final files = FileCollection.dir('dartle');
        expectFiles(files, dirs: ['dartle']);
        await expectEmpty(files.files);
      });
    });
    test('can be created for multiple files', () async {
      await withFileSystem(fs, () async {
        final files = FileCollection.dirs(const ['a', 'b', 'c', 'd', 'e']);
        expectFiles(files, dirs: const ['a', 'b', 'c', 'd', 'e']);
        await expectEmpty(files.files);
      });
    });
  }, timeout: Timeout(Duration(milliseconds: 250)));
}

Future<void> expectEmpty(Stream stream) async {
  expect(await stream.toList(), isEmpty);
}

void expectFiles(FileCollection actual,
    {List<String> files, List<String> dirs}) {
  var index = 0;
  if (files != null) {
    final iter = files.iterator;
    actual.files.listen(expectAsync1((file) {
      if (iter.moveNext()) {
        expect(file.path, equals(iter.current));
      } else {
        fail("Expected a file at index $index, "
            "but the collection has no more files");
      }
      index++;
    }, count: files.length, max: files.length));
  }
  if (dirs != null) {
    index = 0;
    final iter = dirs.iterator;
    actual.directories.listen(expectAsync1((dir) {
      if (iter.moveNext()) {
        expect(dir.path, equals(iter.current));
      } else {
        fail("Expected a directory at index $index, "
            "but the collection has no more files");
      }
      index++;
    }, count: dirs.length, max: dirs.length));
  }
}

class Entry {
  final String _name;
  final List<int> _bytes;
  final bool _isFile;

  Entry.fileWithText(String name, String text)
      : _name = name,
        _isFile = true,
        _bytes = text.runes.toList();

  Entry.fileWithBytes(String name, List<int> bytes)
      : _name = name,
        _isFile = true,
        _bytes = bytes;

  Entry.directory(String name)
      : _name = name,
        _isFile = false,
        _bytes = const [];
}

Future<FileSystem> createFileSystem(List<Entry> entries) async {
  final fs = MemoryFileSystem();
  for (var entry in entries) {
    if (entry._isFile) {
      await fs.file(entry._name).writeAsBytes(entry._bytes);
    } else {
      await fs.directory(entry._name).create(recursive: true);
    }
  }
  return fs;
}
