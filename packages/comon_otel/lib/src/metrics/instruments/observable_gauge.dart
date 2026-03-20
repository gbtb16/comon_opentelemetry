import '../meter.dart';

/// Asynchronous metric instrument that reports the latest observed value.
abstract interface class ObservableGauge<T extends num> {}

/// Callback used to emit measurements for observable instruments.
typedef ObservableCallback<T extends num> =
    void Function(ObservableResult<T> result);
