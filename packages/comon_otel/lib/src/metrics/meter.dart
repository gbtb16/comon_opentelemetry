import '../core/instrumentation_scope.dart';
import '../core/resource.dart';
import 'instruments/counter.dart';
import 'instruments/histogram.dart';
import 'instruments/observable_counter.dart';
import 'instruments/observable_gauge.dart';
import 'instruments/up_down_counter.dart';
import 'meter_provider.dart';
import 'metric_data.dart';

const Map<String, Object> _metricOverflowAttributes = <String, Object>{
  'otel.metric.overflow': true,
};

final class _AttributeSetKey {
  const _AttributeSetKey(this.attributes);

  final Map<String, Object> attributes;

  @override
  bool operator ==(Object other) {
    if (other is! _AttributeSetKey) {
      return false;
    }
    if (attributes.length != other.attributes.length) {
      return false;
    }
    for (final entry in attributes.entries) {
      if (other.attributes[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode {
    var hash = 0;
    for (final entry in attributes.entries) {
      hash ^= Object.hash(entry.key, entry.value);
    }
    return hash;
  }
}

Map<String, Object> _normalizeMetricAttributes(
  Map<String, Object>? attributes,
) {
  if (attributes == null || attributes.isEmpty) {
    return const <String, Object>{};
  }

  return Map<String, Object>.unmodifiable(Map<String, Object>.from(attributes));
}

Map<String, Object> _resolveRetainedAttributes({
  required Map<String, Object> attributes,
  required Map<_AttributeSetKey, Map<String, Object>> retainedAttributeSets,
  required int metricCardinalityLimit,
}) {
  final key = _AttributeSetKey(attributes);
  final retained = retainedAttributeSets[key];
  if (retained != null) {
    return retained;
  }

  if (retainedAttributeSets.length < metricCardinalityLimit) {
    retainedAttributeSets[key] = attributes;
    return attributes;
  }

  return _metricOverflowAttributes;
}

/// Creates metric instruments for a specific instrumentation scope.
final class Meter {
  /// Creates a meter bound to [scope] and backed by [provider].
  Meter({required MeterProvider provider, required this.scope})
    : _provider = provider;

  final MeterProvider _provider;

  /// Instrumentation scope reported on emitted metric data.
  final InstrumentationScope scope;

  /// Name of the current instrumentation scope.
  String get name => scope.name;

  /// Optional version of the current instrumentation scope.
  String? get version => scope.version;

  /// Optional schema URL associated with the instrumentation scope.
  String? get schemaUrl => scope.schemaUrl;

  /// Additional instrumentation scope attributes attached to metric data.
  Map<String, Object> get attributes => scope.attributes;

  /// Creates a monotonic integer counter.
  Counter<int> createIntCounter(
    String name, {
    String? unit,
    String? description,
  }) {
    final instrument = _CounterMetric<int>(
      scope: scope,
      name: name,
      unit: unit,
      description: description,
      instrumentType: MetricInstrumentType.counter,
      allowNegative: false,
    );
    _provider.registerMetric(instrument);
    return instrument;
  }

  /// Creates a monotonic double counter.
  Counter<double> createDoubleCounter(
    String name, {
    String? unit,
    String? description,
  }) {
    final instrument = _CounterMetric<double>(
      scope: scope,
      name: name,
      unit: unit,
      description: description,
      instrumentType: MetricInstrumentType.counter,
      allowNegative: false,
    );
    _provider.registerMetric(instrument);
    return instrument;
  }

  /// Creates an integer up-down counter.
  UpDownCounter<int> createIntUpDownCounter(
    String name, {
    String? unit,
    String? description,
  }) {
    final instrument = _CounterMetric<int>(
      scope: scope,
      name: name,
      unit: unit,
      description: description,
      instrumentType: MetricInstrumentType.upDownCounter,
      allowNegative: true,
    );
    _provider.registerMetric(instrument);
    return instrument;
  }

  /// Creates a double histogram.
  Histogram<double> createHistogram(
    String name, {
    String? unit,
    String? description,
    List<double>? boundaries,
  }) {
    final instrument = _HistogramMetric<double>(
      scope: scope,
      name: name,
      unit: unit,
      description: description,
      boundaries: boundaries,
    );
    _provider.registerMetric(instrument);
    return instrument;
  }

  /// Creates an observable double gauge.
  ObservableGauge<double> createObservableGauge(
    String name, {
    required ObservableCallback<double> callback,
    String? unit,
    String? description,
  }) {
    final instrument = _ObservableMetric<double>(
      scope: scope,
      name: name,
      unit: unit,
      description: description,
      instrumentType: MetricInstrumentType.observableGauge,
      callback: callback,
    );
    _provider.registerMetric(instrument);
    return instrument;
  }

  /// Creates an observable integer counter.
  ObservableCounter<int> createObservableCounter(
    String name, {
    required ObservableCallback<int> callback,
    String? unit,
    String? description,
  }) {
    final instrument = _ObservableMetric<int>(
      scope: scope,
      name: name,
      unit: unit,
      description: description,
      instrumentType: MetricInstrumentType.observableCounter,
      callback: callback,
    );
    _provider.registerMetric(instrument);
    return instrument;
  }
}

/// Collector passed into observable instrument callbacks.
final class ObservableResult<T extends num> {
  /// Creates an observable collection result.
  ObservableResult({required this.metricCardinalityLimit});

  /// Maximum number of distinct attribute sets retained for this collection.
  final int metricCardinalityLimit;
  final Map<_AttributeSetKey, Map<String, Object>> _retainedAttributeSets =
      <_AttributeSetKey, Map<String, Object>>{};
  final List<MetricPoint> _points = <MetricPoint>[];

  /// Records an observation for the current collection cycle.
  void observe(T value, {Map<String, Object>? attributes}) {
    final normalizedAttributes = _normalizeMetricAttributes(attributes);
    _points.add(
      MetricPoint(
        value: value,
        timestamp: DateTime.now().toUtc(),
        attributes: _resolveRetainedAttributes(
          attributes: normalizedAttributes,
          retainedAttributeSets: _retainedAttributeSets,
          metricCardinalityLimit: metricCardinalityLimit,
        ),
      ),
    );
  }
}

final class _Measurement<T extends num> {
  const _Measurement({
    required this.value,
    required this.timestamp,
    this.attributes,
    this.startTimestamp,
  });

  final T value;
  final DateTime timestamp;
  final Map<String, Object>? attributes;
  final DateTime? startTimestamp;
}

final class _CounterMetric<T extends num>
    implements Counter<T>, UpDownCounter<T>, CollectibleMetric {
  _CounterMetric({
    required this.scope,
    required this.name,
    required this.instrumentType,
    required this.allowNegative,
    this.unit,
    this.description,
  });

  final InstrumentationScope scope;
  final String name;
  final String? unit;
  final String? description;
  final MetricInstrumentType instrumentType;
  final bool allowNegative;
  final List<_Measurement<T>> _measurements = <_Measurement<T>>[];
  final Map<_AttributeSetKey, Map<String, Object>> _retainedAttributeSets =
      <_AttributeSetKey, Map<String, Object>>{};

  @override
  void add(T value, {Map<String, Object>? attributes}) {
    if (!allowNegative && value < 0) {
      throw ArgumentError.value(value, 'value', 'Counter values must be >= 0.');
    }
    _measurements.add(
      _Measurement<T>(
        value: value,
        timestamp: DateTime.now().toUtc(),
        attributes: _normalizeMetricAttributes(attributes),
      ),
    );
  }

  @override
  MetricData collect(Resource resource, {required int metricCardinalityLimit}) {
    final aggregated = <_AttributeSetKey, _Measurement<num>>{};

    for (final measurement in _measurements) {
      final attributes = _resolveRetainedAttributes(
        attributes: measurement.attributes ?? const <String, Object>{},
        retainedAttributeSets: _retainedAttributeSets,
        metricCardinalityLimit: metricCardinalityLimit,
      );
      final key = _AttributeSetKey(attributes);
      final existing = aggregated[key];
      if (existing == null) {
        aggregated[key] = _Measurement<num>(
          value: measurement.value,
          timestamp: measurement.timestamp,
          startTimestamp: measurement.timestamp,
          attributes: attributes,
        );
        continue;
      }

      aggregated[key] = _Measurement<num>(
        value: existing.value + measurement.value,
        timestamp: measurement.timestamp,
        startTimestamp: existing.startTimestamp ?? existing.timestamp,
        attributes: attributes,
      );
    }

    return MetricData(
      name: name,
      description: description,
      unit: unit,
      instrumentType: instrumentType,
      resource: resource,
      scope: scope,
      aggregationTemporality: AggregationTemporality.cumulative,
      isMonotonic: !allowNegative,
      points: aggregated.values
          .map(
            (measurement) => MetricPoint(
              value: measurement.value,
              timestamp: measurement.timestamp,
              startTimestamp: measurement.startTimestamp,
              attributes: measurement.attributes ?? const <String, Object>{},
            ),
          )
          .toList(growable: false),
    );
  }
}

final class _HistogramMetric<T extends num>
    implements Histogram<T>, CollectibleMetric {
  _HistogramMetric({
    required this.scope,
    required this.name,
    this.unit,
    this.description,
    this.boundaries,
  });

  final InstrumentationScope scope;
  final String name;
  final String? unit;
  final String? description;
  final List<double>? boundaries;
  final List<_Measurement<T>> _measurements = <_Measurement<T>>[];
  final Map<_AttributeSetKey, Map<String, Object>> _retainedAttributeSets =
      <_AttributeSetKey, Map<String, Object>>{};

  @override
  void record(T value, {Map<String, Object>? attributes}) {
    _measurements.add(
      _Measurement<T>(
        value: value,
        timestamp: DateTime.now().toUtc(),
        attributes: _normalizeMetricAttributes(attributes),
      ),
    );
  }

  @override
  MetricData collect(Resource resource, {required int metricCardinalityLimit}) {
    final grouped = <_AttributeSetKey, List<_Measurement<T>>>{};

    for (final measurement in _measurements) {
      final attributes = _resolveRetainedAttributes(
        attributes: measurement.attributes ?? const <String, Object>{},
        retainedAttributeSets: _retainedAttributeSets,
        metricCardinalityLimit: metricCardinalityLimit,
      );
      grouped
          .putIfAbsent(_AttributeSetKey(attributes), () => <_Measurement<T>>[])
          .add(
            _Measurement<T>(
              value: measurement.value,
              timestamp: measurement.timestamp,
              startTimestamp: measurement.timestamp,
              attributes: attributes,
            ),
          );
    }

    return MetricData(
      name: name,
      description: description,
      unit: unit,
      instrumentType: MetricInstrumentType.histogram,
      resource: resource,
      scope: scope,
      aggregationTemporality: AggregationTemporality.cumulative,
      points: grouped.entries
          .map(
            (entry) =>
                _aggregateHistogramPoint(entry.key.attributes, entry.value),
          )
          .toList(growable: false),
    );
  }

  MetricPoint _aggregateHistogramPoint(
    Map<String, Object> attributes,
    List<_Measurement<T>> measurements,
  ) {
    final values = measurements
        .map((measurement) => measurement.value.toDouble())
        .toList(growable: false);
    final sum = values.fold<double>(0, (total, value) => total + value);
    final min = values.reduce((left, right) => left < right ? left : right);
    final max = values.reduce((left, right) => left > right ? left : right);
    final explicitBounds = boundaries ?? const <double>[];
    final bucketCounts = List<int>.filled(explicitBounds.length + 1, 0);

    for (final value in values) {
      var index = explicitBounds.length;
      for (
        var boundIndex = 0;
        boundIndex < explicitBounds.length;
        boundIndex += 1
      ) {
        if (value <= explicitBounds[boundIndex]) {
          index = boundIndex;
          break;
        }
      }
      bucketCounts[index] += 1;
    }

    return MetricPoint(
      value: sum,
      timestamp: measurements.last.timestamp,
      startTimestamp: measurements.first.timestamp,
      attributes: attributes,
      count: measurements.length,
      sum: sum,
      min: min,
      max: max,
      bucketCounts: bucketCounts,
      explicitBounds: explicitBounds,
    );
  }
}

final class _ObservableMetric<T extends num>
    implements ObservableGauge<T>, ObservableCounter<T>, CollectibleMetric {
  _ObservableMetric({
    required this.scope,
    required this.name,
    required this.instrumentType,
    required this.callback,
    this.unit,
    this.description,
  });

  final InstrumentationScope scope;
  final String name;
  final String? unit;
  final String? description;
  final MetricInstrumentType instrumentType;
  final ObservableCallback<T> callback;

  @override
  MetricData collect(Resource resource, {required int metricCardinalityLimit}) {
    final result = ObservableResult<T>(
      metricCardinalityLimit: metricCardinalityLimit,
    );
    callback(result);
    return MetricData(
      name: name,
      description: description,
      unit: unit,
      instrumentType: instrumentType,
      resource: resource,
      scope: scope,
      aggregationTemporality: switch (instrumentType) {
        MetricInstrumentType.observableCounter =>
          AggregationTemporality.cumulative,
        _ => AggregationTemporality.unspecified,
      },
      isMonotonic: switch (instrumentType) {
        MetricInstrumentType.observableCounter => true,
        _ => null,
      },
      points: List<MetricPoint>.unmodifiable(result._points),
    );
  }
}
