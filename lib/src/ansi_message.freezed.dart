// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target

part of 'ansi_message.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#custom-getters-and-methods');

/// @nodoc
mixin _$AnsiMessagePart {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(ansi.AnsiCode code) code,
    required TResult Function(String text) text,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(ansi.AnsiCode code)? code,
    TResult? Function(String text)? text,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(ansi.AnsiCode code)? code,
    TResult Function(String text)? text,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(Code value) code,
    required TResult Function(Text value) text,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(Code value)? code,
    TResult? Function(Text value)? text,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(Code value)? code,
    TResult Function(Text value)? text,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AnsiMessagePartCopyWith<$Res> {
  factory $AnsiMessagePartCopyWith(
          AnsiMessagePart value, $Res Function(AnsiMessagePart) then) =
      _$AnsiMessagePartCopyWithImpl<$Res, AnsiMessagePart>;
}

/// @nodoc
class _$AnsiMessagePartCopyWithImpl<$Res, $Val extends AnsiMessagePart>
    implements $AnsiMessagePartCopyWith<$Res> {
  _$AnsiMessagePartCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;
}

/// @nodoc
abstract class _$$CodeCopyWith<$Res> {
  factory _$$CodeCopyWith(_$Code value, $Res Function(_$Code) then) =
      __$$CodeCopyWithImpl<$Res>;
  @useResult
  $Res call({ansi.AnsiCode code});
}

/// @nodoc
class __$$CodeCopyWithImpl<$Res>
    extends _$AnsiMessagePartCopyWithImpl<$Res, _$Code>
    implements _$$CodeCopyWith<$Res> {
  __$$CodeCopyWithImpl(_$Code _value, $Res Function(_$Code) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? code = null,
  }) {
    return _then(_$Code(
      null == code
          ? _value.code
          : code // ignore: cast_nullable_to_non_nullable
              as ansi.AnsiCode,
    ));
  }
}

/// @nodoc

class _$Code implements Code {
  const _$Code(this.code);

  @override
  final ansi.AnsiCode code;

  @override
  String toString() {
    return 'AnsiMessagePart.code(code: $code)';
  }

  @override
  bool operator ==(dynamic other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$Code &&
            (identical(other.code, code) || other.code == code));
  }

  @override
  int get hashCode => Object.hash(runtimeType, code);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$CodeCopyWith<_$Code> get copyWith =>
      __$$CodeCopyWithImpl<_$Code>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(ansi.AnsiCode code) code,
    required TResult Function(String text) text,
  }) {
    return code(this.code);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(ansi.AnsiCode code)? code,
    TResult? Function(String text)? text,
  }) {
    return code?.call(this.code);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(ansi.AnsiCode code)? code,
    TResult Function(String text)? text,
    required TResult orElse(),
  }) {
    if (code != null) {
      return code(this.code);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(Code value) code,
    required TResult Function(Text value) text,
  }) {
    return code(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(Code value)? code,
    TResult? Function(Text value)? text,
  }) {
    return code?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(Code value)? code,
    TResult Function(Text value)? text,
    required TResult orElse(),
  }) {
    if (code != null) {
      return code(this);
    }
    return orElse();
  }
}

abstract class Code implements AnsiMessagePart {
  const factory Code(final ansi.AnsiCode code) = _$Code;

  ansi.AnsiCode get code;
  @JsonKey(ignore: true)
  _$$CodeCopyWith<_$Code> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$TextCopyWith<$Res> {
  factory _$$TextCopyWith(_$Text value, $Res Function(_$Text) then) =
      __$$TextCopyWithImpl<$Res>;
  @useResult
  $Res call({String text});
}

/// @nodoc
class __$$TextCopyWithImpl<$Res>
    extends _$AnsiMessagePartCopyWithImpl<$Res, _$Text>
    implements _$$TextCopyWith<$Res> {
  __$$TextCopyWithImpl(_$Text _value, $Res Function(_$Text) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? text = null,
  }) {
    return _then(_$Text(
      null == text
          ? _value.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$Text implements Text {
  const _$Text(this.text);

  @override
  final String text;

  @override
  String toString() {
    return 'AnsiMessagePart.text(text: $text)';
  }

  @override
  bool operator ==(dynamic other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$Text &&
            (identical(other.text, text) || other.text == text));
  }

  @override
  int get hashCode => Object.hash(runtimeType, text);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$TextCopyWith<_$Text> get copyWith =>
      __$$TextCopyWithImpl<_$Text>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(ansi.AnsiCode code) code,
    required TResult Function(String text) text,
  }) {
    return text(this.text);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(ansi.AnsiCode code)? code,
    TResult? Function(String text)? text,
  }) {
    return text?.call(this.text);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(ansi.AnsiCode code)? code,
    TResult Function(String text)? text,
    required TResult orElse(),
  }) {
    if (text != null) {
      return text(this.text);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(Code value) code,
    required TResult Function(Text value) text,
  }) {
    return text(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(Code value)? code,
    TResult? Function(Text value)? text,
  }) {
    return text?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(Code value)? code,
    TResult Function(Text value)? text,
    required TResult orElse(),
  }) {
    if (text != null) {
      return text(this);
    }
    return orElse();
  }
}

abstract class Text implements AnsiMessagePart {
  const factory Text(final String text) = _$Text;

  String get text;
  @JsonKey(ignore: true)
  _$$TextCopyWith<_$Text> get copyWith => throw _privateConstructorUsedError;
}
