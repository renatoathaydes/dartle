import 'dart:io';

/// A consumer of stdout and stderr text streams.
///
/// It expects output line-by-line, typically provided by transforming a stream
/// using [LineSplitter].
///
/// It can be configured to print to stdout, stderr or both, and to keep all
/// lines for possible later inspection.
class StdStreamConsumer {
  final bool printToStdout;
  final bool printToStderr;
  final bool keepLines;
  final bool Function(String) filter;
  final _LinesAccumulator _linesAccumulator;

  StdStreamConsumer(
      {this.printToStdout = false,
      this.printToStderr = false,
      this.keepLines = false,
      this.filter = _noFilter})
      : _linesAccumulator =
            keepLines ? _ActualLinesAccumulator() : _LinesAccumulator();

  /// Consume a line of text.
  void call(String line) {
    final doPrint = filter(line);
    if (doPrint) {
      _linesAccumulator.add(line);
      if (printToStdout) print(line);
      if (printToStderr) stderr.writeln(line);
    }
  }

  /// The lines received by this consumer.
  List<String> get lines => _linesAccumulator.lines;
}

bool _noFilter(String line) => true;

class _LinesAccumulator {
  List<String> get lines => const [];

  void add(String line) {}
}

class _ActualLinesAccumulator implements _LinesAccumulator {
  final List<String> lines = [];

  @override
  void add(String line) => lines.add(line);
}
