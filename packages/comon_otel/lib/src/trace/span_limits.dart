/// Limits applied to attributes, events, and links recorded on spans.
final class SpanLimits {
  /// Creates a set of span limits.
  const SpanLimits({
    this.attributeCountLimit = 128,
    this.eventCountLimit = 128,
    this.linkCountLimit = 128,
    this.attributePerEventCountLimit = 128,
    this.attributePerLinkCountLimit = 128,
  }) : assert(attributeCountLimit >= 0),
       assert(eventCountLimit >= 0),
       assert(linkCountLimit >= 0),
       assert(attributePerEventCountLimit >= 0),
       assert(attributePerLinkCountLimit >= 0);

  /// Maximum number of attributes retained on a span.
  final int attributeCountLimit;

  /// Maximum number of events retained on a span.
  final int eventCountLimit;

  /// Maximum number of links retained on a span.
  final int linkCountLimit;

  /// Maximum number of attributes retained on each span event.
  final int attributePerEventCountLimit;

  /// Maximum number of attributes retained on each span link.
  final int attributePerLinkCountLimit;
}
