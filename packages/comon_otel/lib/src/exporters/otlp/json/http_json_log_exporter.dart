import 'dart:convert';

import '../../../logs/log_record.dart';
import '../../log_exporter.dart';
import '../../span_exporter.dart';
import '../common/exporter_headers.dart';
import '../common/export_response.dart';
import '../common/export_retry.dart';
import '../common/http_transport.dart';
import 'json_codec.dart';

/// OTLP HTTP JSON exporter for logs.
final class OtlpHttpJsonLogExporter implements LogExporter {
  /// Creates an OTLP HTTP JSON log exporter.
  OtlpHttpJsonLogExporter({
    required String endpoint,
    bool appendSignalPath = true,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 10),
    OtlpHttpTransport? transport,
    OtlpCompression compression = OtlpCompression.none,
    OtlpRetryConfig retry = const OtlpRetryConfig(),
  }) : _baseEndpoint = endpoint,
       _appendSignalPath = appendSignalPath,
       _headers = _resolveHeaders(headers, compression),
       _timeout = timeout,
       _transport = transport ?? DefaultOtlpHttpTransport(),
       _compression = compression,
       _retry = retry;

  final String _baseEndpoint;
  final bool _appendSignalPath;
  final Map<String, String> _headers;
  final Duration _timeout;
  final OtlpHttpTransport _transport;
  final OtlpCompression _compression;
  final OtlpRetryConfig _retry;

  @override
  Future<ExportResult> export(List<LogRecord> logs) async {
    return executeOtlpExportWithRetry(
      retry: _retry,
      onSuccessResponse: (response) => handleOtlpHttpSuccessResponse(
        signal: 'logs',
        encoding: OtlpHttpResponseEncoding.json,
        response: response,
      ),
      send: () => _transport.postJson(
        OtlpHttpRequest(
          uri: _appendSignalPath
              ? resolveOtlpSignalUri(_baseEndpoint, '/v1/logs')
              : Uri.parse(_baseEndpoint),
          body: jsonEncode(OtlpJsonCodec.encodeLogs(logs)),
          headers: _headers,
          timeout: _timeout,
          compression: _compression,
        ),
      ),
    );
  }

  static Map<String, String> _resolveHeaders(
    Map<String, String>? headers,
    OtlpCompression compression,
  ) {
    return buildOtlpHttpHeaders(
      contentType: 'application/json',
      compression: compression,
      headers: headers,
    );
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() => _transport.shutdown();
}
