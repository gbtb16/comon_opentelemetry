import '../../core/otel.dart';
import '../../core/semantic_attributes.dart';
import '../../logs/otel_logger.dart';
import '../../metrics/meter.dart';
import '../../trace/span_kind.dart';
import '../../trace/tracer.dart';
import '../../trace/tracer_extensions.dart';
import 'otel_db_metrics.dart';
import 'slow_query_detector.dart';

/// Mixin that wraps database operations with tracing, metrics, and logging.
mixin OtelDatabaseMixin {
  /// Database system name, for example `postgresql` or `mysql`.
  String get dbSystem;

  /// Database name or namespace.
  String get dbName;

  /// Tracer used for database spans.
  Tracer get otelDbTracer => Otel.instance.tracer;

  /// Meter used for database metrics.
  Meter get otelDbMeter => Otel.instance.meter;

  /// Logger used for database logs.
  OtelLogger get otelDbLogger => Otel.instance.logger;

  /// Threshold above which a query is considered slow.
  Duration get slowQueryThreshold => const Duration(milliseconds: 500);

  /// Lazy database metric instruments.
  late final OtelDbMetrics otelDbMetrics = OtelDbMetrics(otelDbMeter);

  /// Helper used to emit slow query warnings.
  SlowQueryDetector get slowQueryDetector =>
      SlowQueryDetector(logger: otelDbLogger, threshold: slowQueryThreshold);

  /// Executes [execute] as an instrumented database operation.
  Future<T> tracedDbOperation<T>(
    String operation, {
    required Future<T> Function() execute,
    String? table,
    String? statement,
    Map<String, Object>? attributes,
    int? Function(T result)? resultCount,
  }) async {
    final operationAttributes = <String, Object>{
      SemanticAttributes.dbSystem: dbSystem,
      SemanticAttributes.dbName: dbName,
      SemanticAttributes.dbOperation: operation,
      ...?table == null
          ? null
          : <String, Object>{SemanticAttributes.dbTable: table},
      ...?statement == null
          ? null
          : <String, Object>{SemanticAttributes.dbStatement: statement},
      ...?attributes,
    };

    return otelDbTracer.traceAsync(
      '$dbSystem.$operation',
      kind: SpanKind.client,
      attributes: operationAttributes,
      fn: () async {
        final stopwatch = Stopwatch()..start();
        otelDbMetrics.operationCounter.add(1, attributes: operationAttributes);
        otelDbMetrics.activeConnections.add(1, attributes: operationAttributes);
        try {
          final result = await execute();
          stopwatch.stop();
          final durationMs = stopwatch.elapsedMicroseconds / 1000;
          otelDbMetrics.operationDuration.record(
            durationMs,
            attributes: operationAttributes,
          );
          final rows = resultCount?.call(result);
          if (rows != null) {
            otelDbMetrics.resultSetSize.record(
              rows.toDouble(),
              attributes: operationAttributes,
            );
          }
          slowQueryDetector.check(
            operation: operation,
            statement: statement,
            duration: stopwatch.elapsed,
            attributes: operationAttributes,
          );
          return result;
        } catch (error, stackTrace) {
          stopwatch.stop();
          otelDbMetrics.errorCounter.add(1, attributes: operationAttributes);
          otelDbLogger.error(
            'DB operation failed',
            attributes: operationAttributes,
            error: error,
            stackTrace: stackTrace,
          );
          rethrow;
        } finally {
          otelDbMetrics.activeConnections.add(
            -1,
            attributes: operationAttributes,
          );
        }
      },
    );
  }
}
