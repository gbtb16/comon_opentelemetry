/// Built-in exporter presets that [Otel.init] can assemble automatically.
enum OtelExporter {
  /// Writes signals to stdout for local development.
  console,

  /// Exports signals through OTLP over HTTP using protobuf payloads.
  otlpHttp,

  /// Exports signals through OTLP over HTTP using JSON payloads.
  otlpHttpJson,

  /// Exports signals through OTLP over gRPC.
  otlpGrpc,
}
