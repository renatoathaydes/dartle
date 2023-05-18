import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as paths;

import '_log.dart';
import '_project.dart';
import 'helpers.dart';

final _capitalLetterPattern = RegExp(r'[A-Z]');

const pubspec = 'pubspec.yaml';
const dartToolDir = '.dartle_tool';

Future<void> runPubGet(_) async {
  await execProc(Process.start('dart', const ['pub', 'get']),
      name: 'Dart pub get', successMode: StreamRedirectMode.stdoutAndStderr);
}

Future<void> checkProjectInit(bool doNotExit, [bool pubGet = true]) async {
  final dartleFile = File('dartle.dart');
  if (await dartleFile.exists()) {
    logger.finer('Dartle file exists.');
    if (!await _findPubSpec()) {
      logger.fine(() => '$pubspec was not found');
      await onNoPubSpec(doNotExit);
    }
  } else {
    await onNoDartleFile(doNotExit);
  }
  if (pubGet && !await _findDartToolDir()) {
    logger.info('Dart dependencies not downloaded yet. Executing '
        "'dart pub get'");
    await runPubGet(const []);
  }
}

Future<bool> _findPubSpec() async {
  final e = await findEntity(pubspec, dir: false);
  return e != null;
}

Future<bool> _findDartToolDir() async {
  final e = await findEntity(dartToolDir, dir: true);
  return e != null;
}

Future<FileSystemEntity?> findEntity(String name,
    {required bool dir, int maxDepth = 4}) async {
  var depth = 0;
  var currentDir = Directory.current;
  FileSystemEntity entity(String p) => dir ? Directory(p) : File(p);
  while (depth < maxDepth) {
    final e = entity(paths.join(currentDir.path, name));
    logger.finer(() => 'Checking if ${e.path} exists');
    if (await e.exists()) return e;
    currentDir = currentDir.parent;
    depth++;
  }
  return null;
}

String decapitalize(String text) {
  if (text.startsWith(_capitalLetterPattern)) {
    return text.substring(0, 1).toLowerCase() + text.substring(1);
  }
  return text;
}

/// Splits the words in the given text using camel-case word separation.
///
/// Example: helloWorld become [hello, world].
List<String> splitWords(String text) {
  var idx = text.indexOf(_capitalLetterPattern, text.isEmpty ? 0 : 1);
  if (idx < 0) return [text];
  final result = <String>[decapitalize(text.substring(0, idx))];
  while (idx >= 0 && idx < text.length) {
    var nextIdx = text.indexOf(_capitalLetterPattern, idx + 1);
    if (nextIdx < 0) nextIdx = text.length;
    result.add(decapitalize(text.substring(idx, nextIdx)));
    idx = nextIdx;
  }
  return result;
}

String? findMatchingByWords(String searchText, List<String> options) {
  if (searchText.isEmpty) return null;
  var result = options.firstWhere((opt) => opt == searchText, orElse: () => '');
  // if there's an exact match, return it
  if (result.isNotEmpty) return result;

  // no exact match found, try to find match by words after splitting the text
  final searchTerms = splitWords(searchText);
  optionsLoop:
  for (final option in options) {
    final optionWords = splitWords(option);
    if (optionWords.length < searchTerms.length) continue; // cannot match
    for (var i = 0; i < searchTerms.length; i++) {
      if (!optionWords[i].startsWith(searchTerms[i])) {
        continue optionsLoop;
      }
    }
    // if we get here, we have a match!
    if (result.isEmpty) {
      // only match so far
      result = option;
    } else {
      // but there was already a match, so the search term is ambiguous!
      return null;
    }
  }
  return result.isEmpty ? null : result;
}

/// Get the path of a file system entity such that directories
/// always end with '/', distinguishing them from files.
String entityPath(FileSystemEntity entity) {
  if (entity is Directory && !entity.path.endsWith('/')) {
    return '${entity.path}/';
  }
  return entity.path;
}

/// Retrieve a file system entity from a path obtained from
/// calling [entityPath].
FileSystemEntity fromEntityPath(String path) {
  if (path.endsWith('/')) {
    return Directory(path);
  }
  return File(path);
}

Digest hash(String text) => hashBytes(utf8.encode(text));

Digest hashBytes(List<int> bytes) => sha1.convert(bytes);

const _bufferLength = 4096;

Future<Digest> hashFile(File file) async {
  final sink = AccumulatorSink<Digest>();
  final converter = sha1.startChunkedConversion(sink);
  final fileHandle = await file.open(mode: FileMode.read);
  try {
    final buffer = Uint8List(_bufferLength);
    var isLast = false;
    while (!isLast) {
      final count = await fileHandle.readInto(buffer);
      isLast = count < _bufferLength;
      converter.addSlice(buffer, 0, count, isLast);
    }
    converter.close();
    return sink.events.single;
  } finally {
    await fileHandle.close();
  }
}

Digest hashAll(Iterable<List<int>> items) {
  final sink = AccumulatorSink<Digest>();
  final converter = sha1.startChunkedConversion(sink);
  for (final item in items) {
    converter.add(item);
  }
  converter.close();
  return sink.events.single;
}

/// Check if the directory is empty safely.
/// Instead of failing, returns `false` on error.
Future<bool> isEmptyDir(String path) async {
  final dir = Directory(path);
  try {
    return await dir.list().isEmpty;
  } catch (e) {
    return false;
  }
}

String elapsedTime(Stopwatch stopwatch) {
  final millis = stopwatch.elapsedMilliseconds;
  if (millis > 1000) {
    final secs = (millis * 1e-3).toStringAsPrecision(4);
    return '$secs seconds';
  } else {
    return '$millis ms';
  }
}

extension AsyncUtil<T> on Stream<T> {
  Future<bool> asyncAny(Future<bool> Function(T) predicate) async {
    await for (final element in this) {
      if (await predicate(element)) return true;
    }
    return false;
  }
}

extension MultiMapUtils<K, V> on Map<K, Set<V>> {
  void accumulate(K key, V value) {
    var current = this[key];
    if (current == null) {
      current = <V>{};
      this[key] = current;
    }
    current.add(value);
  }
}

extension StreamUtils<T> on Stream<T> {
  Stream<T> followedBy(Stream<T> next) async* {
    yield* this;
    yield* next;
  }
}
