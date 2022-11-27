/// A Message that can be logged by the Dartle logger without using the
/// logging pattern, and potentially adding terminal styling such as with
/// [ColoredLogMessage] and [AnsiMessage].
mixin Message {
  /// The message to be printed out.
  ///
  /// The [useColor] argument should be used to determine whether to use color
  /// or any other styling in the returned Object.
  Object getPrintable(bool useColor);

  /// This is called by the logging system even if the message is not logged,
  /// so do not override this! Use [value] to return the actual printable
  /// representation of this message.
  @override
  String toString() => 'Message';
}

/// A [Message] that is always printed in "plain text"
/// (i.e. no colors or styles, no log formatting).
class PlainMessage with Message {
  final Object value;

  const PlainMessage(this.value);

  @override
  Object getPrintable(bool useColor) => value;
}
