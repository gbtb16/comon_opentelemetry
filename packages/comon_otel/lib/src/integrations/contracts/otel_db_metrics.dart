import '../../metrics/instruments/counter.dart';
import '../../metrics/instruments/histogram.dart';
import '../../metrics/instruments/up_down_counter.dart';
import '../../metrics/meter.dart';

/// Database metric instruments created by [OtelDatabaseMixin].
final class OtelDbMetrics {
  /// Creates the database metric instruments using [meter].
  OtelDbMetrics(Meter meter, {this.metricPrefix = 'db.client'})
    : operationCounter = meter.createIntCounter(
        'db.client.operation.count',
        description: 'Number of DB operations',
      ),
      operationDuration = meter.createHistogram(
        'db.client.operation.duration',
        unit: 'ms',
        description: 'DB operation latency',
        boundaries: const <double>[1, 5, 10, 25, 50, 100, 250, 500, 1000],
      ),
      activeConnections = meter.createIntUpDownCounter(
        'db.client.connections.active',
        description: 'Active DB connections',
      ),
      resultSetSize = meter.createHistogram(
        'db.client.result_set.size',
        unit: '{rows}',
        description: 'Number of rows in result set',
      ),
      errorCounter = meter.createIntCounter(
        'db.client.error.count',
        description: 'Number of DB errors',
      );

  /// Prefix reserved for database client metrics.
  final String metricPrefix;

  /// Counts database operations.
  final Counter<int> operationCounter;

  /// Records database operation duration in milliseconds.
  final Histogram<double> operationDuration;

  /// Tracks active database connections.
  final UpDownCounter<int> activeConnections;

  /// Records result-set sizes.
  final Histogram<double> resultSetSize;

  /// Counts failed database operations.
  final Counter<int> errorCounter;
}
