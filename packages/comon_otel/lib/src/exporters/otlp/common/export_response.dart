import 'dart:convert';

import 'http_transport.dart';

/// Encodings supported when parsing successful OTLP HTTP responses.
enum OtlpHttpResponseEncoding { json, protobuf }

/// Handles a successful OTLP HTTP response and reports partial success signals.
void handleOtlpHttpSuccessResponse({
  required String signal,
  required OtlpHttpResponseEncoding encoding,
  required OtlpHttpResponse response,
}) {
  final partialSuccess = switch (encoding) {
    OtlpHttpResponseEncoding.json => _parseJsonPartialSuccess(response.body),
    OtlpHttpResponseEncoding.protobuf => _parseProtobufPartialSuccess(
      response.rawBody,
    ),
  };

  if (partialSuccess == null || !partialSuccess.hasSignal) {
    return;
  }

  print(
    '[comon_otel] OTLP HTTP partial success for $signal export: '
    'rejected=${partialSuccess.rejectedCount}, '
    'message=${partialSuccess.errorMessage}',
  );
}

/// Handles a successful OTLP gRPC response and reports partial success signals.
void handleOtlpGrpcSuccessResponse({
  required String signal,
  required List<int> responseBytes,
}) {
  final partialSuccess = _parseProtobufPartialSuccess(responseBytes);
  if (partialSuccess == null || !partialSuccess.hasSignal) {
    return;
  }

  print(
    '[comon_otel] OTLP gRPC partial success for $signal export: '
    'rejected=${partialSuccess.rejectedCount}, '
    'message=${partialSuccess.errorMessage}',
  );
}

final class _PartialSuccess {
  const _PartialSuccess({
    required this.rejectedCount,
    required this.errorMessage,
  });

  final int rejectedCount;
  final String errorMessage;

  bool get hasSignal => rejectedCount > 0 || errorMessage.isNotEmpty;
}

_PartialSuccess? _parseJsonPartialSuccess(String body) {
  if (body.trim().isEmpty) {
    return null;
  }

  final decoded = jsonDecode(body);
  if (decoded is! Map<String, Object?>) {
    return null;
  }

  final partialSuccess = decoded['partialSuccess'];
  if (partialSuccess is! Map<String, Object?>) {
    return null;
  }

  return _PartialSuccess(
    rejectedCount: _readRejectedCountFromJson(partialSuccess),
    errorMessage: (partialSuccess['errorMessage'] as String?) ?? '',
  );
}

int _readRejectedCountFromJson(Map<String, Object?> partialSuccess) {
  const keys = <String>[
    'rejectedSpans',
    'rejectedDataPoints',
    'rejectedLogRecords',
    'rejectedProfiles',
  ];

  for (final key in keys) {
    final value = partialSuccess[key];
    if (value is int) {
      return value;
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
  }

  return 0;
}

_PartialSuccess? _parseProtobufPartialSuccess(List<int> bytes) {
  if (bytes.isEmpty) {
    return null;
  }

  final reader = _ProtoReader(bytes);
  while (!reader.isAtEnd) {
    final tag = reader.readVarint();
    final fieldNumber = tag >> 3;
    final wireType = tag & 0x07;

    if (fieldNumber == 1 && wireType == 2) {
      final partialBytes = reader.readLengthDelimited();
      return _parsePartialSuccessMessage(partialBytes);
    }

    reader.skipField(wireType);
  }

  return null;
}

_PartialSuccess _parsePartialSuccessMessage(List<int> bytes) {
  var rejectedCount = 0;
  var errorMessage = '';
  final reader = _ProtoReader(bytes);

  while (!reader.isAtEnd) {
    final tag = reader.readVarint();
    final fieldNumber = tag >> 3;
    final wireType = tag & 0x07;

    switch ((fieldNumber, wireType)) {
      case (1, 0):
        rejectedCount = reader.readVarint();
      case (2, 2):
        errorMessage = utf8.decode(reader.readLengthDelimited());
      default:
        reader.skipField(wireType);
    }
  }

  return _PartialSuccess(
    rejectedCount: rejectedCount,
    errorMessage: errorMessage,
  );
}

final class _ProtoReader {
  _ProtoReader(this._bytes);

  final List<int> _bytes;
  int _offset = 0;

  bool get isAtEnd => _offset >= _bytes.length;

  int readVarint() {
    var shift = 0;
    var result = 0;

    while (true) {
      if (_offset >= _bytes.length) {
        throw const FormatException('Unexpected end of protobuf varint.');
      }

      final byte = _bytes[_offset++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) {
        return result;
      }
      shift += 7;
    }
  }

  List<int> readLengthDelimited() {
    final length = readVarint();
    final end = _offset + length;
    if (end > _bytes.length) {
      throw const FormatException('Unexpected end of protobuf bytes.');
    }

    final value = _bytes.sublist(_offset, end);
    _offset = end;
    return value;
  }

  void skipField(int wireType) {
    switch (wireType) {
      case 0:
        readVarint();
      case 1:
        _offset += 8;
      case 2:
        final length = readVarint();
        _offset += length;
      case 5:
        _offset += 4;
      default:
        throw FormatException('Unsupported protobuf wire type: $wireType');
    }

    if (_offset > _bytes.length) {
      throw const FormatException(
        'Unexpected end while skipping protobuf field.',
      );
    }
  }
}
