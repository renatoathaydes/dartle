import 'package:dartle/src/_log.dart';
import 'package:dartle/src/_utils.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main([List<String> args = const []]) {
  if (args.contains('log')) {
    activateLogging();
    setLogLevel(Level.FINE);
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
}
