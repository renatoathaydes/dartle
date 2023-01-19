import 'dart:async';
import 'dart:io' as io;
import 'dart:math';

import 'package:dartle/dartle.dart';
import 'package:dartle/src/_log.dart';
import 'package:isolate_current_directory/isolate_current_directory.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final rand = Random();

class DartleTestFileSystem {
  final String _root;

  const DartleTestFileSystem(this._root);

  String get root => _root;

  io.File file(String path) =>
      Zone.root.runUnary((String f) => io.File(p.join(_root, f)), path);

  io.Directory directory(String path) =>
      Zone.root.runUnary((String d) => io.Directory(p.join(_root, d)), path);
}

DartleTestFileSystem createTempFileSystem() {
  final systemTemp = io.Directory.systemTemp;
  final tempDir =
      io.Directory(p.join(systemTemp.path, 'dartle-temp-${rand.nextDouble()}'));
  tempDir.createSync();
  return DartleTestFileSystem(tempDir.path);
}

FutureOr<R> withFileSystem<R>(
    DartleTestFileSystem fs, FutureOr<R> Function() action) {
  logger.fine(() => 'Using file system with root at: ${fs.root}');
  return withCurrentDirectory(fs.root, () async => await action());
}

Future<ProcessResult> startProcess(
    Future<io.Process> process, String name) async {
  final stdout = StdStreamConsumer(keepLines: true);
  final stderr = StdStreamConsumer(keepLines: true);
  final code = await exec(process,
      name: name, onStdoutLine: stdout, onStderrLine: stderr);
  return ProcessResult(stdout, stderr, code);
}

TaskInvocation taskInvocation(String name, [List<String> args = const []]) {
  return TaskInvocation(TaskWithDeps(Task((_) => null, name: name)), args);
}

class ProcessResult {
  final StdStreamConsumer _stdout;
  final StdStreamConsumer _stderr;
  final int exitCode;

  ProcessResult(this._stdout, this._stderr, this.exitCode);

  List<String> get stdout => _stdout.lines;

  List<String> get stderr => _stderr.lines;

  @override
  String toString() => 'ProcessResult{stdout: $stdout, '
      'stderr: $stderr, '
      'exitCode: $exitCode}';
}

/// Change Windows path to Unix path if needed.
String fixPath(String p) => io.Platform.isWindows ? p.replaceAll('\\', '/') : p;

Future<void> expectFileTree(String rootDir, Map<String, String?> fileTree,
    {DartleTestFileSystem fs = const DartleTestFileSystem('.'),
    bool checkFileContents = true}) async {
  for (final entry in fileTree.entries) {
    final path = entry.key;
    if (entry.value == null) continue;
    final file = (path.endsWith('/')
        ? fs.directory
        : fs.file)(p.join(rootDir, entry.key));
    expect(await file.exists(), isTrue,
        reason: '$file does not exist. '
            'Actual tree: ${await _collectFileTree(fs, rootDir)}');
    if (checkFileContents && file is io.File) {
      expect(await file.readAsString(), equals(entry.value),
          reason: 'file ${file.path} has incorrect contents');
    }
  }

  final absRootDir = fs.directory(rootDir);

  // make sure no extra files exist
  await for (final entity in absRootDir.list(recursive: true)) {
    if (entity is io.File) {
      final path = p.relative(entity.path, from: absRootDir.path);
      if (!fileTree.containsKey(path)) {
        fail('Unexpected file in outputDir: $path. '
            'Actual tree: ${await _collectFileTree(fs, rootDir)}');
      }
    }
  }
}

Future<String?> _collectFileTree(DartleTestFileSystem fs, String dir) async {
  final rootDir = fs.directory(dir);
  if (await rootDir.exists()) {
    StringBuffer buf = StringBuffer('\n');
    await for (final f in rootDir.list(recursive: true)) {
      buf.write(p.relative(f.path, from: fs.root));
      buf.write('\n');
    }
    return buf.toString();
  }
  return 'Empty';
}
