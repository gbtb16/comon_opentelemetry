import '../core/instrumentation_scope.dart';
import '../core/resource.dart';

enum MetricInstrumentType {
  counter,
  upDownCounter,
  histogram,
  observableGauge,
  observableCounter,
}

enum AggregationTemporality { unspecified, delta, cumulative }

final class MetricPoint {
  const MetricPoint({
    this.value,
    required this.timestamp,
    this.startTimestamp,
    this.attributes = const <String, Object>{},
    this.count,
    this.sum,
    this.min,
    this.max,
    this.bucketCounts,
    this.explicitBounds,
  });

  final num? value;
  final DateTime timestamp;
  final DateTime? startTimestamp;
  final Map<String, Object> attributes;
  final int? count;
  final double? sum;
  final double? min;
  final double? max;
  final List<int>? bucketCounts;
  final List<double>? explicitBounds;
}

final class MetricData {
  const MetricData({
    required this.name,
    required this.instrumentType,
    required this.resource,
    required this.points,
    this.description,
    this.unit,
    this.scope,
    this.aggregationTemporality = AggregationTemporality.unspecified,
    this.isMonotonic,
  });

  final String name;
  final String? description;
  final String? unit;
  final MetricInstrumentType instrumentType;
  final Resource resource;
  final List<MetricPoint> points;
  final InstrumentationScope? scope;
  String? get instrumentationScope => scope?.name;
  final AggregationTemporality aggregationTemporality;
  final bool? isMonotonic;
}
