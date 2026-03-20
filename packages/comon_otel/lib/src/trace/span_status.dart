/// Canonical status values reported on a completed span.
enum SpanStatus {
  /// No explicit success or failure status has been set.
  unset,

  /// The span completed successfully.
  ok,

  /// The span completed with an application-level error.
  error,
}
