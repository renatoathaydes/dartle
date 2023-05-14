import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

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
/// determined by looking at the provided [successCodes] Set.
///
/// In case the process exit code is a failure, this method throws a
/// [ProcessExitCodeException].
///
/// By default, both streams are redirected in case of failure, but none in case
/// of success.
Future<int> execProc(Future<Process> process,
    {String name = '',
    Set<int> successCodes = const {0},
    StreamRedirectMode successMode = StreamRedirectMode.none,
    StreamRedirectMode errorMode = StreamRedirectMode.stdoutAndStderr}) async {
  final allDisabled = successMode == StreamRedirectMode.none &&
      errorMode == StreamRedirectMode.none;
  final stdoutConsumer = StdStreamConsumer(keepLines: !allDisabled);
  final stderrConsumer = StdStreamConsumer(keepLines: !allDisabled);
  final code = await _exec(await process, name, stdoutConsumer, stderrConsumer);
  final success = successCodes.contains(code);
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

  await redirect(successCodes.contains(code) ? successMode : errorMode);
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
/// is not in the [successCodes] Set, or [ProcessException] in case the
/// process could not be executed at all.
///
Future<ExecReadResult> execRead(Future<Process> process,
    {String name = '',
    bool Function(String) stdoutFilter = filterNothing,
    bool Function(String) stderrFilter = filterNothing,
    Set<int> successCodes = const {0}}) async {
  final stdout = StdStreamConsumer(keepLines: true, filter: stdoutFilter);
  final stderr = StdStreamConsumer(keepLines: true, filter: stderrFilter);
  final code = await _exec(await process, name, stdout, stderr);
  final result = ExecReadResult(code, stdout.lines, stderr.lines);
  if (successCodes.contains(code)) {
    return result;
  }
  throw ProcessExitCodeException(code, name, stdout.lines, stderr.lines);
}

/// Download binary data from the given [Uri].
///
/// It is possible to configure [HttpHeaders] and [Cookie]s sent to the server
/// by providing the functions [headers] and [cookies], respectively.
///
/// A response is considered successful if its status code is in the
/// [successfulStatusCodes] Set. If the status code is not in this Set,
/// a [HttpCodeException] is thrown.
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
    Set<int> successfulStatusCodes = defaultSuccessfulStatusCodes,
    Duration connectionTimeout = const Duration(seconds: 10)}) async* {
  final client = HttpClient()..connectionTimeout = connectionTimeout;
  final req = await client.getUrl(uri);
  try {
    req.persistentConnection = false;
    headers?.call(req.headers);
    cookies?.call(req.cookies);
    final res = await req.close();
    if (successfulStatusCodes.contains(res.statusCode)) {
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
/// A response is considered successful if its status code is in the
/// [successfulStatusCodes] Set. If the status code is not in this Set,
/// a [HttpCodeException] is thrown.
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
    Set<int> successfulStatusCodes = defaultSuccessfulStatusCodes,
    Duration connectionTimeout = const Duration(seconds: 10),
    Encoding encoding = utf8}) async {
  return download(uri,
          headers: headers,
          cookies: cookies,
          connectionTimeout: connectionTimeout,
          successfulStatusCodes: successfulStatusCodes)
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
/// A response is considered successful if its status code is in the
/// [successfulStatusCodes] Set. If the status code is not in this Set,
/// a [HttpCodeException] is thrown.
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
    Set<int> successfulStatusCodes = defaultSuccessfulStatusCodes,
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
          successfulStatusCodes: successfulStatusCodes,
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

Future<void> _gzipEncode(InputStreamBase input, OutputStreamBase output) async {
  final gzip = GZipEncoder();
  gzip.encode(input, output: output);
  await input.close();
  if (output is OutputFileStream) {
    await output.close();
  }
}

/// Tar all files in the given fileCollection into the destination file.
///
/// The destination file is overwritten if it already exists.
///
/// By default, the tar contents are gzipped. By passing an `encoder` function,
/// it's possible to use other encoding, or no encoding at all.
///
/// The tar file is returned.
///
Future<File> tar(FileCollection fileCollection,
    {required String destination,
    String Function(String)? destinationPath,
    Future<Object?> Function(InputStreamBase, OutputStreamBase) encoder =
        _gzipEncode}) async {
  final tarEncoder = TarFileEncoder();
  final tempTar = tempFile(extension: '.tar');
  tarEncoder.create(tempTar.path);
  await for (final file in fileCollection.resolveFiles()) {
    final path = destinationPath?.call(file.path) ?? file.path;
    await tarEncoder.addFile(file, path);
  }
  await tarEncoder.close();

  final dest = File(destination);
  await dest.parent.create(recursive: true);

  final tarStream = InputFileStream(tempTar.path);
  final destinationStream = OutputFileStream(destination);
  try {
    await encoder(tarStream, destinationStream);
  } finally {
    await ignoreExceptions(() async => await tempTar.delete());
  }
  return dest;
}

/// Untar a tar file's contents into the given destinationDir.
///
/// A `decode` function can be provided to decode the tarFile before its
/// contents are unpacked. The function must return the path to the decoded
/// file, typically in a temporary location (the file is not deleted).
///
/// By default, the tarFile is assumed to be gzipped if its name ends
/// with either `.tar.gz` or `.tgz`, otherwise the tarFile is assumed to be
/// a simple tar archive.
///
/// The destination directory is created if necessary and returned.
Future<Directory> untar(String tarFile,
    {required String destinationDir, String Function()? decode}) async {
  String tarPath;
  if (decode == null) {
    if (tarFile.endsWith('.tar.gz') || tarFile.endsWith('.tgz')) {
      tarPath = tempFile().path;
      final inStream = InputFileStream(tarFile);
      final outStream = OutputFileStream(tarPath);
      GZipDecoder().decodeStream(inStream, outStream);
      inStream.close();
      outStream.close();
    } else {
      tarPath = tarFile;
    }
  } else {
    tarPath = decode();
  }
  final tarStream = InputFileStream(tarPath);
  final archive = TarDecoder().decodeBuffer(tarStream);
  try {
    for (final entry in archive) {
      final name = entry.name
          .split('/')
          .where((e) => e != '..' && e != '.')
          .where((e) => e.trim().isNotEmpty)
          .join(Platform.pathSeparator);
      if (entry.isFile && name.isNotEmpty) {
        final output = File(p.join(destinationDir, name));
        await output.parent.create(recursive: true);
        final outStream = OutputFileStream(output.path);
        entry.writeContent(outStream);
        await outStream.close();
      } else {
        await Directory(p.join(destinationDir, name)).create(recursive: true);
      }
    }
  } finally {
    await tarStream.close();
  }
  return Directory(destinationDir);
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
}
