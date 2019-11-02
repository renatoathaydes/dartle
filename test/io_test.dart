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
        ...['dartle', 'a', 'b', 'c', 'd', 'A/B/C', 'A/B/D', 'A/B/D/E']
            .map((d) => Entry.directory(d)),
        Entry.fileWithText('dartle.dart', 'hello world'),
        Entry.fileWithText('dartle/some.txt', 'text'),
        Entry.fileWithText('b/b.txt', 'BBBB'),
        Entry.fileWithText('A/B/C/c.txt', 'CCCC'),
        Entry.fileWithText('A/B/D/d.txt', 'DDDD'),
        Entry.fileWithText('A/B/D/E/e.txt', 'EEEE'),
      ]);
    });
    test('can be created for a single file', () async {
      final files = file('dartle.dart');
      await expectFiles(files, files: ['dartle.dart']);
      await expectEmpty(files.directories);
    });
    test('can be created for multiple files', () async {
      final allFiles = files(const ['a', 'b', 'c', 'd', 'e']);
      await expectFiles(allFiles, files: const ['a', 'b', 'c', 'd', 'e']);
      await expectEmpty(allFiles.directories);
    });
    test('can be created for multiple file entities', () async {
      final files =
          FileCollection([fs.file('dartle/some.txt'), fs.file('dartle.dart')]);
      await expectFiles(files, files: const ['dartle.dart', 'dartle/some.txt']);
      await expectEmpty(files.directories);
    });

    // FileCollections containing directories require them to exist
    test('can be created for a single directory', () async {
      await withFileSystem(fs, () async {
        final files = dir('a');
        await expectFiles(files, dirs: ['a']);
        await expectEmpty(files.files);
      });
    });
    test('can be created for multiple directories', () async {
      await withFileSystem(fs, () async {
        final files = dirs(const ['a', 'b', 'c', 'd']);
        await expectFiles(files,
            files: const ['b/b.txt'], dirs: const ['a', 'b', 'c', 'd']);
      });
    });
    test('can be created for multiple directories with filters', () async {
      await withFileSystem(fs, () async {
        final files = dirs(const ['dartle', 'b', 'c', 'A'],
            fileFilter: (file) => file.path != 'b/b.txt',
            dirFilter: (dir) => dir.path.contains('A/B'));
        await expectFiles(files, files: [
          'A/B/C/c.txt',
          'A/B/D/d.txt',
          'A/B/D/E/e.txt',
          'dartle/some.txt',
        ], dirs: const [
          'A',
          'b',
          'c',
          'dartle',
        ]);
      });
    });
    test('can be created for multiple entities with filters', () async {
      await withFileSystem(fs, () async {
        final files = FileCollection([
          fs.directory('dartle'),
          fs.directory('b'),
          fs.directory('c'),
          fs.directory('A/B'),
          fs.file('A/B/D/E/e.txt'),
        ],
            fileFilter: (file) => file.path != 'b/b.txt',
            dirFilter: (dir) => !dir.path.startsWith("A/B/D"));
        await expectFiles(files,
            files: ['A/B/D/E/e.txt', 'A/B/C/c.txt', 'dartle/some.txt'],
            dirs: const ['A/B', 'b', 'c', 'dartle']);
      });
    });
  }, timeout: Timeout(Duration(milliseconds: 250)));
}

Future<void> expectEmpty(Stream stream) async {
  expect(await stream.toList(), isEmpty);
}

Future expectFiles(FileCollection actual,
    {List<String> files = const [], List<String> dirs = const []}) async {
  var index = 0;
  if (files.isNotEmpty) {
    final iter = files.iterator;
    await for (final file in actual.files) {
      if (iter.moveNext()) {
        expect(file.path, equals(iter.current), reason: 'file at index $index');
      } else {
        fail("Found a file at index $index, "
            "but expected no more files: ${file.path}");
      }
      index++;
    }
  }
  if (dirs.isNotEmpty) {
    index = 0;
    final iter = dirs.iterator;
    await for (final dir in actual.directories) {
      if (iter.moveNext()) {
        expect(dir.path, equals(iter.current), reason: 'dir at index $index');
      } else {
        fail("Found a directory at index $index, "
            "but expected no more files: ${dir.path}");
      }
      index++;
    }
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
