import 'dart:io';

import 'package:dartle/dartle.dart';
import 'package:dartle/src/_utils.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_utils.dart';

void main([List<String> args = const []]) {
  if (args.contains('log')) {
    activateLogging(Level.FINE);
  }

  test('decapitalize', () {
    expect(decapitalize(''), equals(''));
    expect(decapitalize('A'), equals('a'));
    expect(decapitalize('ab'), equals('ab'));
    expect(decapitalize('Ab'), equals('ab'));
    expect(decapitalize('aB'), equals('aB'));
    expect(decapitalize('AB'), equals('aB'));
    expect(decapitalize('hiWorldFooBar'), equals('hiWorldFooBar'));
    expect(decapitalize('HiWorldFooBar'), equals('hiWorldFooBar'));
  });

  test('splitWords', () {
    expect(splitWords(''), equals(['']));
    expect(splitWords('hi'), equals(['hi']));
    expect(splitWords('hi-world'), equals(['hi-world']));
    expect(splitWords('hiWorld'), equals(['hi', 'world']));
    expect(splitWords('HiWorld'), equals(['hi', 'world']));
    expect(splitWords('theCatAteTheBook'),
        equals(['the', 'cat', 'ate', 'the', 'book']));
    expect(splitWords('FooBarZ'), equals(['foo', 'bar', 'z']));
    expect(splitWords('aBCdE'), equals(['a', 'b', 'cd', 'e']));
  });

  test('findMatchingByWords', () {
    expect(findMatchingByWords('', []), isNull);
    expect(findMatchingByWords('', ['hi']), isNull);
    expect(findMatchingByWords('', ['a', 'b', 'c']), isNull);
    expect(findMatchingByWords('a', ['a', 'b', 'c']), equals('a'));
    expect(findMatchingByWords('b', ['a', 'b', 'c']), equals('b'));
    expect(findMatchingByWords('c', ['a', 'b', 'c']), equals('c'));
    expect(findMatchingByWords('d', ['a', 'b', 'c']), isNull);
    expect(findMatchingByWords('hi', ['hiWorld', 'hiYou']), isNull);
    expect(findMatchingByWords('hiWorld', ['hiWorld', 'hiYou']),
        equals('hiWorld'));
    expect(findMatchingByWords('hiW', ['hiWorld', 'hiYou']), equals('hiWorld'));
    expect(findMatchingByWords('hiY', ['hiWorld', 'hiYou']), equals('hiYou'));

    expect(
        findMatchingByWords(
            '', const ['fooBar', 'fooBarBaz', 'test', 'check', 'fooBarFoo']),
        isNull);
    expect(
        findMatchingByWords('fooBar',
            const ['fooBar', 'fooBarBaz', 'test', 'check', 'fooBarFoo']),
        equals('fooBar'));
    expect(
        findMatchingByWords('fooBarZ',
            const ['fooBar', 'fooBarBaz', 'test', 'check', 'fooBarFoo']),
        isNull);
    expect(
        findMatchingByWords(
            'fBB', const ['fooBar', 'fooBarBaz', 'test', 'check', 'fooBarFoo']),
        'fooBarBaz');
    expect(
        findMatchingByWords('foBaB',
            const ['fooBar', 'fooBarBaz', 'test', 'check', 'fooBarFoo']),
        'fooBarBaz');
    expect(
        findMatchingByWords('fooBarB',
            const ['fooBar', 'fooBarBaz', 'test', 'check', 'fooBarFoo']),
        'fooBarBaz');
    expect(
        findMatchingByWords('fooBarF',
            const ['fooBar', 'fooBarBaz', 'test', 'check', 'fooBarFoo']),
        equals('fooBarFoo'));
    expect(
        findMatchingByWords('fooBFo',
            const ['fooBar', 'fooBarBaz', 'test', 'check', 'fooBarFoo']),
        equals('fooBarFoo'));
    expect(
        findMatchingByWords('fooBarFoo',
            const ['fooBar', 'fooBarBaz', 'test', 'check', 'fooBarFoo']),
        equals('fooBarFoo'));
    expect(
        findMatchingByWords(
            't', const ['fooBar', 'fooBarBaz', 'test', 'check', 'fooBarFoo']),
        equals('test'));
    expect(
        findMatchingByWords('test',
            const ['fooBar', 'fooBarBaz', 'test', 'check', 'fooBarFoo']),
        equals('test'));
    expect(
        findMatchingByWords(
            'c', const ['fooBar', 'fooBarBaz', 'test', 'check', 'fooBarFoo']),
        equals('check'));
    expect(
        findMatchingByWords(
            'che', const ['fooBar', 'fooBarBaz', 'test', 'check', 'fooBarFoo']),
        equals('check'));
    expect(
        findMatchingByWords('check',
            const ['fooBar', 'fooBarBaz', 'test', 'check', 'fooBarFoo']),
        equals('check'));
    expect(
        findMatchingByWords(
            'f', const ['fooBar', 'fooBarBaz', 'test', 'check', 'fooBarFoo']),
        isNull);
  });

  group('deleteAll', () {
    DartleTestFileSystem fs = createTempFileSystem();
    Directory? foo, bar;
    File? txtFile, mdFile, barTxtFile, barMdFile;
    setUp(() async {
      fs = createTempFileSystem();
      foo = fs.directory('foo');
      txtFile = fs.file(p.join('foo', 'file.txt'));
      mdFile = fs.file(p.join('foo', 'file.md'));
      bar = fs.directory(p.join('foo', 'bar'));
      barTxtFile = fs.file(p.join('foo', 'bar', 'file.txt'));
      barMdFile = fs.file(p.join('foo', 'bar', 'file.md'));
      await bar!.create(recursive: true);
      for (var f in [txtFile!, mdFile!, barTxtFile!, barMdFile!]) {
        await f.create();
      }
    });

    test('full directory', () async {
      // make sure the file tree was created correctly
      expect(
          await Directory(fs.root)
              .list(recursive: true)
              .map((e) => e.path)
              .toSet(),
          equals({foo!, bar!, txtFile!, mdFile!, barTxtFile!, barMdFile!}
              .map((e) => e.path)
              .toSet()));

      // actual test
      await withFileSystem(fs, () async {
        await deleteAll(dir('foo'));
      });
      expect(await Directory(fs.root).list(recursive: true).toList(), isEmpty);
    });

    test('sub-directory', () async {
      await withFileSystem(fs, () async {
        await deleteAll(dir(p.join('foo', 'bar')));
      });
      expect(
          await Directory(fs.root)
              .list(recursive: true)
              .map((e) => e.path)
              .toSet(),
          equals({foo!, txtFile!, mdFile!}.map((e) => e.path).toSet()));
    });

    test('directory with pattern', () async {
      await withFileSystem(fs, () async {
        await deleteAll(dir('foo', fileExtensions: {'.md', '.jpg'}));
      });
      expect(
          await Directory(fs.root)
              .list(recursive: true)
              .map((e) => e.path)
              .toSet(),
          equals(
              {foo!, bar!, txtFile!, barTxtFile!}.map((e) => e.path).toSet()));
    });

    test('directory with pattern matching everything', () async {
      await withFileSystem(fs, () async {
        await deleteAll(dir('foo', fileExtensions: {'.md', '.txt'}));
      });
      expect(await Directory(fs.root).list(recursive: true).toSet(), isEmpty);
    });

    test('directory with file exclusion', () async {
      await withFileSystem(fs, () async {
        await deleteAll(dir('foo', exclusions: const {'file.txt'}));
      });
      expect(
          await Directory(fs.root)
              .list(recursive: true)
              .map((e) => e.path)
              .toSet(),
          equals(
              {foo!, bar!, txtFile!, barTxtFile!}.map((e) => e.path).toSet()));
    });

    test('directory with directory exclusion', () async {
      await withFileSystem(fs, () async {
        await deleteAll(dir('foo', exclusions: const {'bar'}));
      });
      expect(
          await Directory(fs.root)
              .list(recursive: true)
              .map((e) => e.path)
              .toSet(),
          equals({foo!, bar!, barTxtFile!, barMdFile!}
              .map((e) => e.path)
              .toSet()));
    });
  });
}
