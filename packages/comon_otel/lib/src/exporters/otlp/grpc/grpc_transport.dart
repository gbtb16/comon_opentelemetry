import 'package:grpc/grpc.dart' as grpc;

import '../common/http_transport.dart';

/// OTLP signal types supported by the gRPC transport.
enum OtlpSignal { traces, metrics, logs }

/// Request sent through an [OtlpGrpcTransport].
final class OtlpGrpcRequest {
  /// Creates an OTLP gRPC request.
  const OtlpGrpcRequest({
    required this.uri,
    required this.signal,
    required this.body,
    required this.headers,
    required this.timeout,
    this.compression = OtlpCompression.none,
  });

  /// Target collector URI.
  final Uri uri;

  /// OTLP signal being exported.
  final OtlpSignal signal;

  /// Encoded protobuf payload.
  final List<int> body;

  /// Call metadata headers.
  final Map<String, String> headers;

  /// Per-request timeout.
  final Duration timeout;

  /// Compression applied to the request.
  final OtlpCompression compression;
}

/// Exception thrown by [OtlpGrpcTransport] implementations.
final class OtlpGrpcTransportException implements Exception {
  /// Creates a transport exception.
  const OtlpGrpcTransportException(this.message, {required this.retryable});

  /// Human-readable error message.
  final String message;

  /// Whether the failed request may be retried.
  final bool retryable;

  @override
  String toString() => 'OtlpGrpcTransportException($message)';
}

/// Transport used by OTLP gRPC exporters.
abstract interface class OtlpGrpcTransport {
  /// Exports a gRPC request.
  Future<List<int>> export(OtlpGrpcRequest request);

  /// Releases transport resources.
  Future<void> shutdown();
}

/// IO-backed OTLP gRPC transport using `package:grpc` channels.
final class IoOtlpGrpcTransport implements OtlpGrpcTransport {
  final Map<String, grpc.ClientChannel> _channels =
      <String, grpc.ClientChannel>{};

  @override
  Future<List<int>> export(OtlpGrpcRequest request) async {
    final channel = _channels.putIfAbsent(
      _channelKey(request.uri),
      () => _createChannel(request.uri),
    );
    final client = _RawGrpcClient(channel);

    try {
      return await client.export(
        signal: request.signal,
        body: request.body,
        headers: request.headers,
        timeout: request.timeout,
        compression: request.compression,
      );
    } on grpc.GrpcError catch (error) {
      throw OtlpGrpcTransportException(
        error.message ?? error.toString(),
        retryable: _isRetryableCode(error.code),
      );
    } catch (error) {
      throw OtlpGrpcTransportException(error.toString(), retryable: true);
    }
  }

  @override
  Future<void> shutdown() async {
    for (final channel in _channels.values) {
      await channel.shutdown();
    }
    _channels.clear();
  }

  static String _channelKey(Uri uri) =>
      '${uri.scheme}://${uri.host}:${uri.port}';

  static grpc.ClientChannel _createChannel(Uri uri) {
    return grpc.ClientChannel(
      uri.host,
      port: uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80),
      options: grpc.ChannelOptions(
        credentials: uri.scheme == 'https'
            ? const grpc.ChannelCredentials.secure()
            : const grpc.ChannelCredentials.insecure(),
        codecRegistry: grpc.CodecRegistry(
          codecs: const <grpc.Codec>[grpc.GzipCodec()],
        ),
      ),
    );
  }

  static bool _isRetryableCode(int code) {
    return code == grpc.StatusCode.deadlineExceeded ||
        code == grpc.StatusCode.resourceExhausted ||
        code == grpc.StatusCode.aborted ||
        code == grpc.StatusCode.internal ||
        code == grpc.StatusCode.unavailable ||
        code == grpc.StatusCode.unknown;
  }
}

final class _RawGrpcClient extends grpc.Client {
  _RawGrpcClient(super.channel);

  static final grpc.ClientMethod<List<int>, List<int>> _traceMethod =
      grpc.ClientMethod<List<int>, List<int>>(
        '/opentelemetry.proto.collector.trace.v1.TraceService/Export',
        (List<int> value) => value,
        (List<int> value) => value,
      );

  static final grpc.ClientMethod<List<int>, List<int>> _metricMethod =
      grpc.ClientMethod<List<int>, List<int>>(
        '/opentelemetry.proto.collector.metrics.v1.MetricsService/Export',
        (List<int> value) => value,
        (List<int> value) => value,
      );

  static final grpc.ClientMethod<List<int>, List<int>> _logMethod =
      grpc.ClientMethod<List<int>, List<int>>(
        '/opentelemetry.proto.collector.logs.v1.LogsService/Export',
        (List<int> value) => value,
        (List<int> value) => value,
      );

  Future<List<int>> export({
    required OtlpSignal signal,
    required List<int> body,
    required Map<String, String> headers,
    required Duration timeout,
    required OtlpCompression compression,
  }) async {
    final method = switch (signal) {
      OtlpSignal.traces => _traceMethod,
      OtlpSignal.metrics => _metricMethod,
      OtlpSignal.logs => _logMethod,
    };

    final callOptions = grpc.CallOptions(
      metadata: headers,
      timeout: timeout,
      compression: compression == OtlpCompression.gzip
          ? const grpc.GzipCodec()
          : null,
    );

    return await $createUnaryCall(method, body, options: callOptions);
  }
}
