import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:tar/tar.dart';

import '_log.dart';
import '_std_stream_consumer.dart';
import 'error.dart';
import 'file_collection.dart';
import 'run_condition.dart';
import 'task.dart';

/// Location of the dartle directory within a project.
const dartleDir = '.dartle_tool';

/// The default successful status codes for HTTP responses.
const defaultSuccessfulStatusCodes = {200, 201, 202, 203, 204};

bool _isSuccessfulStatusCode(int code) =>
    defaultSuccessfulStatusCodes.contains(code);

/// Fail the build for the given [reason].
///
/// This function never returns.
Never failBuild({required String reason, int exitCode = 1}) {
  throw DartleException(message: reason, exitCode: exitCode);
}

/// Run the given action ignoring any Exceptions thrown by it.
/// Returns `true` if the action succeeded, `false` otherwise.
FutureOr<bool> ignoreExceptions(FutureOr Function() action) async {
  try {
    await action();
    return true;
  } on Exception {
    // ignore
    return false;
  }
}

/// Get the user HOME directory if possible.
String? homeDir() => Platform.isWindows
    ? Platform.environment['USERPROFILE']
    : Platform.environment['HOME'];

/// Executes the given process, returning its exit code.
///
/// [onStdoutLine] and [onStderrLine] can be provided in order to consume
/// the process' stdout and stderr streams, respectively (the process's output
/// is interpreted as utf8 emitted line by line).
///
/// If not provided, the streams are consumed and printed to stdout or stderr,
/// respectively.
///
/// Instances of [StdStreamConsumer] can be used as [onStdoutLine] and
/// [onStderrLine] functions in order to easily configure what to do with the
/// process' output.
Future<int> exec(Future<Process> process,
    {String name = '',
    Function(String)? onStdoutLine,
    Function(String)? onStderrLine}) async {
  final proc = await process;
  onStdoutLine ??= StdStreamConsumer(printToStdout: true);
  onStderrLine ??= StdStreamConsumer(printToStderr: true);

  return _exec(proc, name, onStdoutLine, onStderrLine);
}

Future<int> _exec(Process proc, String name, Function(String) onStdoutLine,
    Function(String) onStderrLine) async {
  final procDescription = "process${name.isEmpty ? '' : " '$name'"} "
      '(PID=${proc.pid})';
  logger.fine('Started $procDescription');

  final streamsDone = StreamController<bool>();

  proc.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(onStdoutLine, onDone: () => streamsDone.add(true));
  proc.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(onStderrLine, onDone: () => streamsDone.add(true));

  final code = await proc.exitCode;
  logger.fine('$procDescription exited with code $code');

  // block until the streams are done
  await streamsDone.stream.take(2).last;

  return code;
}

/// Defines which stream(s) should be redirected to the calling process' streams
/// from another running [Process] when using the [execProc] function.
enum StreamRedirectMode { stdout, stderr, stdoutAndStderr, none }

/// Executes the given process, returning its exit code.
///
/// This method is similar to [exec], but simpler to use for cases where
/// it is desirable to redirect the process' streams and automatically fail
/// depending on the exit code.
///
/// A [StreamRedirectMode] can be provided to configure whether the process'
/// output should be redirected to the calling process's streams in case of
/// success or failure. Whether the result is a success or a failure is
/// determined by the [isCodeSuccessful] function (only 0 is success, by default).
///
/// This method throws [ProcessExitCodeException] in case the process' exit code
/// is not considered successful by [isCodeSuccessful],
/// or [ProcessException] in case the process could not be executed at all.
///
/// By default, both streams are redirected in case of failure, but none in case
/// of success.
Future<int> execProc(Future<Process> process,
    {String name = '',
    bool Function(int) isCodeSuccessful = _onlyZero,
    StreamRedirectMode successMode = StreamRedirectMode.none,
    StreamRedirectMode errorMode = StreamRedirectMode.stdoutAndStderr}) async {
  final allDisabled = successMode == StreamRedirectMode.none &&
      errorMode == StreamRedirectMode.none;
  final stdoutConsumer = StdStreamConsumer(keepLines: !allDisabled);
  final stderrConsumer = StdStreamConsumer(keepLines: !allDisabled);
  final code = await _exec(await process, name, stdoutConsumer, stderrConsumer);
  final success = isCodeSuccessful(code);
  if (allDisabled) {
    if (success) {
      return code;
    } else {
      throw ProcessExitCodeException(
          code, name, stdoutConsumer.lines, stderrConsumer.lines);
    }
  }
  Future<void> redirect(StreamRedirectMode mode) async {
    switch (mode) {
      case StreamRedirectMode.none:
        break;
      case StreamRedirectMode.stderr:
        stderr
          ..writeAll(stderrConsumer.lines, '\n')
          ..writeln();
        break;
      case StreamRedirectMode.stdout:
        stdout
          ..writeAll(stdoutConsumer.lines, '\n')
          ..writeln();
        break;
      case StreamRedirectMode.stdoutAndStderr:
        stdout
          ..writeAll(stdoutConsumer.lines, '\n')
          ..writeln();
        stderr
          ..writeAll(stderrConsumer.lines, '\n')
          ..writeln();
    }
  }

  await redirect(success ? successMode : errorMode);
  if (success) {
    return code;
  }
  throw ProcessExitCodeException(
      code, name, stdoutConsumer.lines, stderrConsumer.lines);
}

/// Result of calling [execRead].
///
/// The `stdout` and `stderr` lists contain the process output, line by line.
class ExecReadResult {
  final int exitCode;
  final List<String> stdout;
  final List<String> stderr;

  const ExecReadResult(this.exitCode, this.stdout, this.stderr);
}

bool _onlyZero(int i) => i == 0;

/// Executes the given process, returning its output streams line-by-line.
///
/// This method is similar to [exec], but simplifying the process of reading
/// the process output into Lists.
///
/// The returned object contains the process stdout and stderr outputs as
/// `Lists<String>` where each item is a line of output.
///
/// Output lines may be filtered out by providing [stdoutFilter] or [stderrFilter]
/// (the filter must return `true` to keep a line, or `false` to exclude it).
///
/// This method throws [ProcessExitCodeException] in case the process' exit code
/// is not considered successful by [isCodeSuccessful],
/// or [ProcessException] in case the process could not be executed at all.
///
Future<ExecReadResult> execRead(Future<Process> process,
    {String name = '',
    bool Function(String) stdoutFilter = filterNothing,
    bool Function(String) stderrFilter = filterNothing,
    bool Function(int) isCodeSuccessful = _onlyZero}) async {
  final stdout = StdStreamConsumer(keepLines: true, filter: stdoutFilter);
  final stderr = StdStreamConsumer(keepLines: true, filter: stderrFilter);
  final code = await _exec(await process, name, stdout, stderr);
  final result = ExecReadResult(code, stdout.lines, stderr.lines);
  if (isCodeSuccessful(code)) {
    return result;
  }
  throw ProcessExitCodeException(code, name, stdout.lines, stderr.lines);
}

/// Download binary data from the given [Uri].
///
/// It is possible to configure [HttpHeaders] and [Cookie]s sent to the server
/// by providing the functions [headers] and [cookies], respectively.
///
/// A response is considered successful if the [isSuccessfulStatusCode]
/// function returns `true`. If it is not, an [HttpCodeException] is thrown.
/// By default, [defaultSuccessfulStatusCodes] is used.
///
/// A [connectionTimeout] may be provided.
///
/// This method opens a single connection to make a GET request, and closes
/// that connection before returning, so it is not suitable for making
/// several requests to the same server efficiently.
///
Stream<List<int>> download(Uri uri,
    {void Function(HttpHeaders)? headers,
    void Function(List<Cookie>)? cookies,
    bool Function(int) isSuccessfulStatusCode = _isSuccessfulStatusCode,
    Duration connectionTimeout = const Duration(seconds: 10)}) async* {
  final client = HttpClient()..connectionTimeout = connectionTimeout;
  final req = await client.getUrl(uri);
  try {
    req.persistentConnection = false;
    headers?.call(req.headers);
    cookies?.call(req.cookies);
    final res = await req.close();
    if (isSuccessfulStatusCode(res.statusCode)) {
      yield* res;
    } else {
      throw HttpCodeException(res, uri);
    }
  } finally {
    client.close();
  }
}

/// Download plain text from the given [Uri].
///
/// It is possible to configure [HttpHeaders] and [Cookie]s sent to the server
/// by providing the functions [headers] and [cookies], respectively.
///
/// A response is considered successful if the [isSuccessfulStatusCode]
/// function returns `true`. If it is not, an [HttpCodeException] is thrown.
/// By default, [defaultSuccessfulStatusCodes] is used.
///
/// A [connectionTimeout] and an [Encoding] (UTF-8 by default) may be provided.
///
/// This method opens a single connection to make a GET request, and closes
/// that connection before returning, so it is not suitable for making
/// several requests to the same server efficiently.
///
Future<String> downloadText(Uri uri,
    {void Function(HttpHeaders)? headers,
    void Function(List<Cookie>)? cookies,
    bool Function(int) isSuccessfulStatusCode = _isSuccessfulStatusCode,
    Duration connectionTimeout = const Duration(seconds: 10),
    Encoding encoding = utf8}) async {
  return download(uri,
          headers: headers,
          cookies: cookies,
          connectionTimeout: connectionTimeout,
          isSuccessfulStatusCode: isSuccessfulStatusCode)
      .transform(encoding.decoder)
      .join();
}

/// Download JSON data from the given [Uri].
///
/// It is possible to configure [HttpHeaders] and [Cookie]s sent to the server
/// by providing the functions [headers] and [cookies], respectively.
///
/// By default, the `Accept` header is set to `application/json`.
///
/// A response is considered successful if the [isSuccessfulStatusCode]
/// function returns `true`. If it is not, an [HttpCodeException] is thrown.
/// By default, [defaultSuccessfulStatusCodes] is used.
///
/// A [connectionTimeout] and an [Encoding] (UTF-8 by default) may be provided.
///
/// This method opens a single connection to make a GET request, and closes
/// that connection before returning, so it is not suitable for making
/// several requests to the same server efficiently.
///
Future<Object?> downloadJson(Uri uri,
    {void Function(HttpHeaders)? headers,
    void Function(List<Cookie>)? cookies,
    bool Function(int) isSuccessfulStatusCode = _isSuccessfulStatusCode,
    Duration connectionTimeout = const Duration(seconds: 10),
    Encoding encoding = utf8}) {
  void withJsonHeader(HttpHeaders h) {
    h.add(
        HttpHeaders.acceptHeader,
        "${ContentType.json.mimeType}"
        "${encoding == utf8 ? '' : '; charset=${encoding.name}'}");
    headers?.call(h);
  }

  return download(uri,
          headers: withJsonHeader,
          cookies: cookies,
          isSuccessfulStatusCode: isSuccessfulStatusCode,
          connectionTimeout: connectionTimeout)
      .transform(encoding.decoder)
      .transform(json.decoder)
      .first;
}

/// Get the outputs of a [Task].
///
/// This method can only return the outputs of a Task if its [RunCondition]
/// implements [FilesCondition], otherwise `null` is returned.
FileCollection? taskOutputs(Task task) {
  switch (task.runCondition) {
    case FilesCondition(outputs: var out):
      return out;
    default:
      return null;
  }
}

/// Deletes the outputs of all [tasks].
///
/// This method only works if the task's [RunCondition]s are instances of
/// [FilesCondition].
Future<void> deleteOutputs(Iterable<Task> tasks) async {
  for (final task in tasks) {
    final outputs = taskOutputs(task);
    if (outputs != null) {
      await deleteAll(outputs);
    }
  }
}

/// Delete all files and possibly directories included in the given
/// [fileCollection].
///
/// Directories are only deleted if after deleting all
/// [FileCollection.files], the directories end up being empty. In other words,
/// directories are deleted as long as no filters belonging to the given
/// [FileCollection] exclude files or sub-directories within such directory.
Future<void> deleteAll(FileCollection fileCollection) async {
  final toDelete = await fileCollection.resolve().toList();
  // the list is in listed-files order, so we must reverse it to delete
  // directories last.
  for (final entry in toDelete.reversed) {
    logger.fine('Deleting ${entry.path}');
    final ok =
        await ignoreExceptions(() => entry.entity.delete(recursive: false));
    if (!ok) {
      logger.warning('Failed to delete: ${entry.path}');
    }
  }
}

final _random = Random();

/// Get a [File] with a random name inside the `Directory.systemTemp` directory.
///
/// The file is created automatically.
File tempFile({String extension = ''}) {
  final dir = Directory.systemTemp.path;
  return File(
      p.join(dir, 'dtemp-${_random.nextInt(pow(2, 31).toInt())}$extension'))
    ..createSync();
}

/// Get a [Directory] with a random name inside the `Directory.systemTemp` directory.
///
/// The directory is created automatically.
Directory tempDir({String suffix = ''}) {
  final dir = Directory.systemTemp.path;
  return Directory(
      p.join(dir, 'dtemp-${_random.nextInt(pow(2, 31).toInt())}$suffix'))
    ..createSync();
}

Stream<TarEntry> _tarEntries(
    Stream<File> files, String Function(String)? destinationPath) async* {
  await for (final file in files) {
    final path = destinationPath?.call(file.path) ?? file.path;
    final stat = file.statSync();
    yield TarEntry(
        TarHeader(name: path, mode: stat.mode, modified: stat.modified),
        file.openRead());
  }
}

/// Tar all files in the given fileCollection into the destination file.
///
/// The destination file is overwritten if it already exists.
///
/// If `encoder` is `null` (the default), the tarFile will be gzipped
/// in case its name ends with either `.tar.gz` or `.tgz`, or use no further
/// encoding otherwise.
///
/// Provide an `encoder` explicitly to use another
/// encoding, or no encoding at all by using [NoEncoding].
///
/// A `destinationPath` function can be provided to map source file paths into
/// destination paths. That allows the path inside the tar archive to be chosen
/// for each included file. By default, the path of the source file is also used
/// for its destination path inside the tar.
///
/// The tar file is returned.
///
Future<File> tar(FileCollection fileCollection,
    {required String destination,
    String Function(String)? destinationPath,
    Converter<List<int>, List<int>>? encoder}) async {
  logger.finer(() => 'Tar $fileCollection to $destination');
  final entries = _tarEntries(fileCollection.resolveFiles(), destinationPath);
  final dest = File(destination);
  await dest.parent.create(recursive: true);
  await entries
      .transform(tarWriter)
      .transform(encoder ?? gzip.encoder)
      .pipe(dest.openWrite());
  return dest;
}

/// Untar a tar file's contents into the given destinationDir.
///
/// If `decoder` is provided, it's used to decode the file contents before
/// processing it (e.g. [gzip.decoder] could be used to decode the file).
///
/// If `decoder` is `null` (the default), the tarFile is assumed to be gzipped
/// in case its name ends with either `.tar.gz` or `.tgz`, or to be a simple
/// tar archive otherwise.
///
/// Use [NoEncoding] to ensure the tar is always treated as a plain archive.
///
/// If a tar entry's name has any `..` or `.` components in its path,
/// these components are removed.
///
/// File permissions are set only on MacOS and Linux. The `lastModified` value
/// is set for all created files.
///
/// The destination directory is created if necessary and returned.
Future<Directory> untar(String tarFile,
    {required String destinationDir,
    Converter<List<int>, List<int>>? decoder}) async {
  logger.finer(() => 'Untar $tarFile');
  var tarStream = File(tarFile).openRead();
  if (decoder == null) {
    if (tarFile.endsWith('.tar.gz') || tarFile.endsWith('.tgz')) {
      tarStream = tarStream.transform(gzip.decoder);
    }
  } else {
    tarStream = tarStream.transform(decoder);
  }
  final tarReader = TarReader(tarStream);

  while (await tarReader.moveNext()) {
    final entry = tarReader.current;
    final name = entry.name
        .split('/')
        .where((e) => e != '..' && e != '.')
        .where((e) => e.trim().isNotEmpty)
        .join(Platform.pathSeparator);
    if (entry.type == TypeFlag.dir) {
      logger.finer(() => 'Extracting tar entry directory: $name');
      await Directory(p.join(destinationDir, name)).create(recursive: true);
    } else if (entry.type case TypeFlag.reg || TypeFlag.regA) {
      final mode = (0xfff & entry.header.mode).toRadixString(8);
      logger.finer(() => 'Extracting tar entry file: $name (mode=$mode)');
      final output = File(p.join(destinationDir, name));
      await output.parent.create(recursive: true);
      final outStream = output.openWrite();
      await entry.contents.pipe(outStream);
      await output.setLastModified(entry.header.modified);
      await output._setPermissions(mode);
    } else {
      logger.fine(
          () => 'Ignoring tar entry with unrecognized typeFlag: ${entry.type}');
    }
  }
  return Directory(destinationDir);
}

/// A no-op implementation of [Converter].
class NoEncoding extends Converter<List<int>, List<int>> {
  const NoEncoding();

  @override
  List<int> convert(List<int> input) {
    return input;
  }

  @override
  Sink<List<int>> startChunkedConversion(Sink<List<int>> sink) {
    return ByteConversionSink.from(sink);
  }
}

extension FileHelpers on File {
  /// Write a binary stream to a file.
  ///
  /// Creates the parent directory if necessary.
  ///
  /// If [makeExecutable] is set to `true`, this method attempts to make this
  /// [File] executable. This currently only works on Linux and MacOS.
  Future<File> writeBinary(
    Stream<List<int>> stream, {
    bool makeExecutable = false,
  }) async {
    await parent.create(recursive: true);
    final handle = openWrite();
    try {
      await handle.addStream(stream);
      await handle.flush();
    } finally {
      await handle.close();
    }
    if (makeExecutable && (Platform.isLinux || Platform.isMacOS)) {
      final exitCode = await execProc(
          Process.start('chmod', ['+x', path], runInShell: true));
      if (exitCode != 0) {
        throw DartleException(message: 'Unable to make file $path executable');
      }
    }
    return this;
  }

  Future<void> _setPermissions(String unixPermissions) async {
    if (!(Platform.isLinux || Platform.isMacOS)) return;
    try {
      await execProc(Process.start('chmod', [unixPermissions, path]),
          name: 'chmod');
    } on ProcessExitCodeException catch (e) {
      logger.fine('Unable to set file permissions ($path), '
          'chmod exitCode=${e.exitCode}');
    }
  }
}
