import '../context/otel_context.dart';
import 'span_context.dart';
import 'span_kind.dart';
import 'span_link.dart';
import 'trace_id.dart';
import 'trace_state.dart';

/// Result returned by a [Sampler] decision.
final class SamplerResult {
  /// Creates a sampler result.
  const SamplerResult({
    required this.sampled,
    bool? recording,
    this.traceState,
    this.attributes,
  }) : recording = recording ?? sampled,
       assert(sampled == false || recording != false);

  /// Whether the span should be marked as sampled.
  final bool sampled;

  /// Whether the span should record attributes, events, and links.
  final bool recording;

  /// Trace state to propagate on the resulting span context.
  final TraceState? traceState;

  /// Additional attributes produced by the sampler.
  final Map<String, Object>? attributes;
}

/// Input passed into composable or classic samplers.
final class SamplingRequest {
  /// Creates a sampling request.
  SamplingRequest({
    required this.traceId,
    required this.name,
    required this.kind,
    this.parentSnapshot,
    SpanContext? parentContext,
    this.attributes,
    this.links,
  }) : parentContext = parentSnapshot?.spanContext ?? parentContext;

  /// Trace ID being evaluated.
  final TraceId traceId;

  /// Requested span name.
  final String name;

  /// Requested span kind.
  final SpanKind kind;

  /// Parent snapshot, when available.
  final OtelContextSnapshot? parentSnapshot;

  /// Parent span context resolved from the snapshot or explicit context.
  final SpanContext? parentContext;

  /// Proposed span attributes.
  final Map<String, Object>? attributes;

  /// Proposed span links.
  final List<SpanLink>? links;
}

/// Intermediate decision format used by [ComposableSampler] implementations.
final class SamplingIntent {
  /// Creates a composable sampling intent.
  const SamplingIntent({
    this.threshold,
    required this.thresholdReliable,
    this.attributes,
    this.traceState,
  }) : assert(
         threshold == null || (threshold >= 0 && threshold < _maxThreshold),
       ),
       assert(threshold != null || thresholdReliable == false);

  /// Threshold used to compare against the trace randomness value.
  final int? threshold;

  /// Whether the threshold can be safely written back to `tracestate`.
  final bool thresholdReliable;

  /// Attributes to attach when the request is sampled.
  final Map<String, Object>? attributes;

  /// Trace state to propagate for the sampling decision.
  final TraceState? traceState;
}

/// Predicate used by [ComposableRuleBased] to select a delegate sampler.
typedef ComposablePredicate = bool Function(SamplingRequest request);

/// Sampler building block that emits a [SamplingIntent].
abstract interface class ComposableSampler {
  /// Creates a composable sampler.
  const ComposableSampler();

  /// Returns the sampling intent for [request].
  SamplingIntent getSamplingIntent(SamplingRequest request);
}

/// Adapter that turns a [ComposableSampler] tree into a standard [Sampler].
final class CompositeSampler implements Sampler {
  /// Creates a sampler backed by a composable sampler tree.
  const CompositeSampler({required this.root});

  /// Root composable sampler.
  final ComposableSampler root;

  @override
  SamplerResult decide({
    required TraceId traceId,
    required String name,
    required SpanKind kind,
    OtelContextSnapshot? parentSnapshot,
    SpanContext? parentContext,
    Map<String, Object>? attributes,
    List<SpanLink>? links,
  }) {
    final resolvedParentContext = parentSnapshot?.spanContext ?? parentContext;
    final request = SamplingRequest(
      traceId: traceId,
      name: name,
      kind: kind,
      parentSnapshot: parentSnapshot,
      parentContext: resolvedParentContext,
      attributes: attributes,
      links: links,
    );
    final intent = root.getSamplingIntent(request);
    final sampled = switch (intent.threshold) {
      final int threshold =>
        _resolveRandomnessValue(
              traceId: traceId,
              traceState: resolvedParentContext?.traceStateValue,
            ) >=
            threshold,
      null => false,
    };

    return SamplerResult(
      sampled: sampled,
      traceState: _traceStateForIntent(
        traceState: intent.traceState ?? resolvedParentContext?.traceStateValue,
        sampled: sampled,
        threshold: intent.threshold,
        thresholdReliable: intent.thresholdReliable,
      ),
      attributes: sampled ? intent.attributes : null,
    );
  }

  @override
  bool shouldSample({
    required TraceId traceId,
    required String name,
    required SpanKind kind,
    OtelContextSnapshot? parentSnapshot,
    SpanContext? parentContext,
    Map<String, Object>? attributes,
    List<SpanLink>? links,
  }) {
    return decide(
      traceId: traceId,
      name: name,
      kind: kind,
      parentSnapshot: parentSnapshot,
      parentContext: parentContext,
      attributes: attributes,
      links: links,
    ).sampled;
  }
}

/// Composable sampler that always samples.
final class ComposableAlwaysOn implements ComposableSampler {
  /// Creates an always-on composable sampler.
  const ComposableAlwaysOn();

  @override
  SamplingIntent getSamplingIntent(SamplingRequest request) {
    return const SamplingIntent(threshold: 0, thresholdReliable: true);
  }
}

/// Composable sampler that never samples.
final class ComposableAlwaysOff implements ComposableSampler {
  /// Creates an always-off composable sampler.
  const ComposableAlwaysOff();

  @override
  SamplingIntent getSamplingIntent(SamplingRequest request) {
    return const SamplingIntent(thresholdReliable: false);
  }
}

/// Composable sampler that samples according to a probability ratio.
final class ComposableProbability implements ComposableSampler {
  /// Creates a composable probability sampler.
  ComposableProbability(double ratio)
    : _ratio = ratio.clamp(0, 1).toDouble(),
      _threshold = _thresholdFromRatio(ratio.clamp(0, 1).toDouble());

  final double _ratio;
  final int? _threshold;

  @override
  SamplingIntent getSamplingIntent(SamplingRequest request) {
    if (_ratio <= 0) {
      return const SamplingIntent(thresholdReliable: false);
    }

    return SamplingIntent(threshold: _threshold ?? 0, thresholdReliable: true);
  }
}

/// Composable sampler that reuses the parent threshold when present.
final class ComposableParentThreshold implements ComposableSampler {
  /// Creates a parent-threshold composable sampler.
  const ComposableParentThreshold({required this.root});

  /// Sampler used when there is no parent context.
  final ComposableSampler root;

  @override
  SamplingIntent getSamplingIntent(SamplingRequest request) {
    final parent = request.parentContext;
    if (parent == null) {
      return root.getSamplingIntent(request);
    }

    final threshold = _readThreshold(parent.traceStateValue);
    if (parent.sampled) {
      return SamplingIntent(
        threshold: threshold ?? 0,
        thresholdReliable: threshold != null,
        traceState: _traceStateForIntent(
          traceState: parent.traceStateValue,
          sampled: true,
          threshold: threshold,
          thresholdReliable: threshold != null,
        ),
      );
    }

    return SamplingIntent(
      thresholdReliable: false,
      traceState: _setOtelSubKey(
        traceState: parent.traceStateValue,
        subKey: 'th',
        subValue: null,
      ),
    );
  }
}

/// Rule entry for [ComposableRuleBased].
final class ComposableRule {
  /// Creates a rule with a predicate and delegate sampler.
  const ComposableRule({required this.predicate, required this.delegate});

  /// Predicate deciding whether [delegate] should handle a request.
  final ComposablePredicate predicate;

  /// Sampler used when [predicate] matches.
  final ComposableSampler delegate;
}

/// Composable sampler that evaluates a list of rules in order.
final class ComposableRuleBased implements ComposableSampler {
  /// Creates a rule-based composable sampler.
  const ComposableRuleBased(this.rules);

  /// Ordered rules evaluated against each request.
  final List<ComposableRule> rules;

  @override
  SamplingIntent getSamplingIntent(SamplingRequest request) {
    for (final rule in rules) {
      if (rule.predicate(request)) {
        return rule.delegate.getSamplingIntent(request);
      }
    }

    return const SamplingIntent(thresholdReliable: false);
  }
}

/// Composable sampler that appends attributes to sampled spans.
final class ComposableAnnotating implements ComposableSampler {
  /// Creates an annotating composable sampler.
  ComposableAnnotating({
    required Map<String, Object> attributes,
    required this.delegate,
  }) : _attributes = Map<String, Object>.unmodifiable(attributes);

  final Map<String, Object> _attributes;

  /// Delegate sampler that makes the underlying decision.
  final ComposableSampler delegate;

  @override
  SamplingIntent getSamplingIntent(SamplingRequest request) {
    final delegateIntent = delegate.getSamplingIntent(request);
    return SamplingIntent(
      threshold: delegateIntent.threshold,
      thresholdReliable: delegateIntent.thresholdReliable,
      attributes: <String, Object>{
        ...?delegateIntent.attributes,
        ..._attributes,
      },
      traceState: delegateIntent.traceState,
    );
  }
}

/// Chooses whether a span should be sampled and recorded.
abstract interface class Sampler {
  /// Creates a sampler.
  const Sampler();

  /// Returns the full sampling result for a candidate span.
  SamplerResult decide({
    required TraceId traceId,
    required String name,
    required SpanKind kind,
    OtelContextSnapshot? parentSnapshot,
    SpanContext? parentContext,
    Map<String, Object>? attributes,
    List<SpanLink>? links,
  }) {
    final resolvedParentContext = parentSnapshot?.spanContext ?? parentContext;
    return SamplerResult(
      sampled: shouldSample(
        traceId: traceId,
        name: name,
        kind: kind,
        parentSnapshot: parentSnapshot,
        parentContext: resolvedParentContext,
        attributes: attributes,
        links: links,
      ),
      traceState: resolvedParentContext?.traceStateValue,
    );
  }

  /// Returns whether the candidate span should be sampled.
  bool shouldSample({
    required TraceId traceId,
    required String name,
    required SpanKind kind,
    OtelContextSnapshot? parentSnapshot,
    SpanContext? parentContext,
    Map<String, Object>? attributes,
    List<SpanLink>? links,
  });
}

/// Sampler that always samples and records spans.
final class AlwaysOnSampler implements Sampler {
  /// Creates an always-on sampler.
  const AlwaysOnSampler();

  @override
  SamplerResult decide({
    required TraceId traceId,
    required String name,
    required SpanKind kind,
    OtelContextSnapshot? parentSnapshot,
    SpanContext? parentContext,
    Map<String, Object>? attributes,
    List<SpanLink>? links,
  }) {
    final resolvedParentContext = parentSnapshot?.spanContext ?? parentContext;
    return SamplerResult(
      sampled: true,
      traceState: resolvedParentContext?.traceStateValue,
    );
  }

  @override
  bool shouldSample({
    required TraceId traceId,
    required String name,
    required SpanKind kind,
    OtelContextSnapshot? parentSnapshot,
    SpanContext? parentContext,
    Map<String, Object>? attributes,
    List<SpanLink>? links,
  }) {
    return true;
  }
}

/// Sampler that never samples or records spans.
final class AlwaysOffSampler implements Sampler {
  /// Creates an always-off sampler.
  const AlwaysOffSampler();

  @override
  SamplerResult decide({
    required TraceId traceId,
    required String name,
    required SpanKind kind,
    OtelContextSnapshot? parentSnapshot,
    SpanContext? parentContext,
    Map<String, Object>? attributes,
    List<SpanLink>? links,
  }) {
    final resolvedParentContext = parentSnapshot?.spanContext ?? parentContext;
    return SamplerResult(
      sampled: false,
      traceState: resolvedParentContext?.traceStateValue,
    );
  }

  @override
  bool shouldSample({
    required TraceId traceId,
    required String name,
    required SpanKind kind,
    OtelContextSnapshot? parentSnapshot,
    SpanContext? parentContext,
    Map<String, Object>? attributes,
    List<SpanLink>? links,
  }) {
    return false;
  }
}

/// Samples based on a deterministic ratio derived from the trace ID.
final class TraceIdRatioSampler implements Sampler {
  /// Creates a ratio sampler with a value clamped to the `0..1` range.
  TraceIdRatioSampler(double ratio)
    : _ratio = ratio.clamp(0, 1).toDouble(),
      _threshold = _encodeThresholdValue(
        _thresholdFromRatio(ratio.clamp(0, 1).toDouble()),
      );

  final double _ratio;
  final String? _threshold;

  @override
  SamplerResult decide({
    required TraceId traceId,
    required String name,
    required SpanKind kind,
    OtelContextSnapshot? parentSnapshot,
    SpanContext? parentContext,
    Map<String, Object>? attributes,
    List<SpanLink>? links,
  }) {
    final resolvedParentContext = parentSnapshot?.spanContext ?? parentContext;
    final sampled = shouldSample(
      traceId: traceId,
      name: name,
      kind: kind,
      parentSnapshot: parentSnapshot,
      parentContext: resolvedParentContext,
      attributes: attributes,
      links: links,
    );
    return SamplerResult(
      sampled: sampled,
      traceState: _traceStateForDecision(
        traceState: resolvedParentContext?.traceStateValue,
        sampled: sampled,
      ),
    );
  }

  @override
  bool shouldSample({
    required TraceId traceId,
    required String name,
    required SpanKind kind,
    OtelContextSnapshot? parentSnapshot,
    SpanContext? parentContext,
    Map<String, Object>? attributes,
    List<SpanLink>? links,
  }) {
    if (_ratio <= 0) {
      return false;
    }
    if (_ratio >= 1) {
      return true;
    }

    final prefix = traceId.hex.substring(0, 8);
    final sampleValue = int.parse(prefix, radix: 16) / 0xFFFFFFFF;
    return sampleValue < _ratio;
  }

  TraceState? _traceStateForDecision({
    required TraceState? traceState,
    required bool sampled,
  }) {
    if (!sampled || _threshold == null) {
      return traceState;
    }

    return _setOtelSubKey(
          traceState: traceState,
          subKey: 'th',
          subValue: _threshold,
        ) ??
        traceState;
  }
}

/// Delegates to different samplers depending on the parent span context.
final class ParentBasedSampler implements Sampler {
  /// Creates a parent-based sampler.
  const ParentBasedSampler({
    required this.root,
    this.remoteParentSampled = const AlwaysOnSampler(),
    this.remoteParentNotSampled = const AlwaysOffSampler(),
    this.localParentSampled = const AlwaysOnSampler(),
    this.localParentNotSampled = const AlwaysOffSampler(),
  });

  /// Sampler used when there is no parent context.
  final Sampler root;

  /// Sampler used when the parent is remote and sampled.
  final Sampler remoteParentSampled;

  /// Sampler used when the parent is remote and not sampled.
  final Sampler remoteParentNotSampled;

  /// Sampler used when the parent is local and sampled.
  final Sampler localParentSampled;

  /// Sampler used when the parent is local and not sampled.
  final Sampler localParentNotSampled;

  @override
  SamplerResult decide({
    required TraceId traceId,
    required String name,
    required SpanKind kind,
    OtelContextSnapshot? parentSnapshot,
    SpanContext? parentContext,
    Map<String, Object>? attributes,
    List<SpanLink>? links,
  }) {
    final parent = parentSnapshot?.spanContext ?? parentContext;
    if (parent != null) {
      return _delegateForParent(parent).decide(
        traceId: traceId,
        name: name,
        kind: kind,
        parentSnapshot: parentSnapshot,
        parentContext: parent,
        attributes: attributes,
        links: links,
      );
    }

    return root.decide(
      traceId: traceId,
      name: name,
      kind: kind,
      parentSnapshot: parentSnapshot,
      parentContext: null,
      attributes: attributes,
      links: links,
    );
  }

  @override
  bool shouldSample({
    required TraceId traceId,
    required String name,
    required SpanKind kind,
    OtelContextSnapshot? parentSnapshot,
    SpanContext? parentContext,
    Map<String, Object>? attributes,
    List<SpanLink>? links,
  }) {
    final parent = parentSnapshot?.spanContext ?? parentContext;
    if (parent != null) {
      return _delegateForParent(parent).shouldSample(
        traceId: traceId,
        name: name,
        kind: kind,
        parentSnapshot: parentSnapshot,
        parentContext: parent,
        attributes: attributes,
        links: links,
      );
    }

    return root.shouldSample(
      traceId: traceId,
      name: name,
      kind: kind,
      parentSnapshot: parentSnapshot,
      parentContext: null,
      attributes: attributes,
      links: links,
    );
  }

  Sampler _delegateForParent(SpanContext parent) {
    if (parent.isRemote) {
      return parent.sampled ? remoteParentSampled : remoteParentNotSampled;
    }

    return parent.sampled ? localParentSampled : localParentNotSampled;
  }
}

/// Forces recording even when the delegated sampler does not sample.
final class AlwaysRecordSampler implements Sampler {
  /// Creates an always-record wrapper around [root].
  const AlwaysRecordSampler({required this.root});

  /// Delegate sampler used for the base decision.
  final Sampler root;

  @override
  SamplerResult decide({
    required TraceId traceId,
    required String name,
    required SpanKind kind,
    OtelContextSnapshot? parentSnapshot,
    SpanContext? parentContext,
    Map<String, Object>? attributes,
    List<SpanLink>? links,
  }) {
    final result = root.decide(
      traceId: traceId,
      name: name,
      kind: kind,
      parentSnapshot: parentSnapshot,
      parentContext: parentContext,
      attributes: attributes,
      links: links,
    );
    if (result.recording) {
      return result;
    }

    return SamplerResult(
      sampled: false,
      recording: true,
      traceState: result.traceState,
    );
  }

  @override
  bool shouldSample({
    required TraceId traceId,
    required String name,
    required SpanKind kind,
    OtelContextSnapshot? parentSnapshot,
    SpanContext? parentContext,
    Map<String, Object>? attributes,
    List<SpanLink>? links,
  }) {
    return root.shouldSample(
      traceId: traceId,
      name: name,
      kind: kind,
      parentSnapshot: parentSnapshot,
      parentContext: parentContext,
      attributes: attributes,
      links: links,
    );
  }
}

/// Convenience factory wrapper for sampler creation in [Otel.init].
final class SamplerConfig {
  /// Creates a sampler config from a builder callback.
  const SamplerConfig._(this.build);

  /// Builder that returns the concrete sampler instance.
  final Sampler Function() build;

  /// Creates a config from a custom sampler builder.
  factory SamplerConfig.custom(Sampler Function() build) {
    return SamplerConfig._(build);
  }

  /// Creates a config for [AlwaysOnSampler].
  factory SamplerConfig.alwaysOn() {
    return const SamplerConfig._(AlwaysOnSampler.new);
  }

  /// Creates a config for [AlwaysOffSampler].
  factory SamplerConfig.alwaysOff() {
    return const SamplerConfig._(AlwaysOffSampler.new);
  }

  /// Creates a config for [TraceIdRatioSampler].
  factory SamplerConfig.ratio(double ratio) {
    return SamplerConfig._(() => TraceIdRatioSampler(ratio));
  }

  /// Creates a config for [ParentBasedSampler] with a ratio-based root sampler.
  factory SamplerConfig.parentBased({double rootRatio = 1.0}) {
    return SamplerConfig._(
      () => ParentBasedSampler(root: TraceIdRatioSampler(rootRatio)),
    );
  }

  /// Creates a config for [AlwaysRecordSampler].
  factory SamplerConfig.alwaysRecord({required Sampler root}) {
    return SamplerConfig._(() => AlwaysRecordSampler(root: root));
  }

  /// Creates a config for [CompositeSampler].
  factory SamplerConfig.composite(ComposableSampler root) {
    return SamplerConfig._(() => CompositeSampler(root: root));
  }
}

int _resolveRandomnessValue({
  required TraceId traceId,
  required TraceState? traceState,
}) {
  final explicitRandomness = _readOtelSubKey(traceState, 'rv');
  final parsedRandomness = _parseRandomnessValue(explicitRandomness);
  if (parsedRandomness != null) {
    return parsedRandomness;
  }

  return int.parse(traceId.hex.substring(traceId.hex.length - 14), radix: 16);
}

TraceState? _traceStateForIntent({
  required TraceState? traceState,
  required bool sampled,
  required int? threshold,
  required bool thresholdReliable,
}) {
  if (!sampled || threshold == null || !thresholdReliable) {
    return _setOtelSubKey(traceState: traceState, subKey: 'th', subValue: null);
  }

  return _setOtelSubKey(
    traceState: traceState,
    subKey: 'th',
    subValue: _encodeThresholdValue(threshold),
  );
}

int? _thresholdFromRatio(double ratio) {
  if (ratio <= 0) {
    return null;
  }
  if (ratio >= 1) {
    return 0;
  }

  var threshold = (_maxThreshold * (1 - ratio)).round();
  if (threshold <= 0) {
    return 0;
  }
  if (threshold >= _maxThreshold) {
    threshold = _maxThreshold - 1;
  }
  return threshold;
}

int? _readThreshold(TraceState? traceState) {
  return _parseThresholdValue(_readOtelSubKey(traceState, 'th'));
}

int? _parseThresholdValue(String? value) {
  if (value == null ||
      value.isEmpty ||
      value.length > 14 ||
      !_isLowerHex(value)) {
    return null;
  }

  final padded = value.padRight(14, '0');
  return int.parse(padded, radix: 16);
}

int? _parseRandomnessValue(String? value) {
  if (value == null || value.length != 14 || !_isLowerHex(value)) {
    return null;
  }

  return int.parse(value, radix: 16);
}

String? _encodeThresholdValue(int? threshold) {
  if (threshold == null) {
    return null;
  }
  if (threshold <= 0) {
    return '0';
  }

  final encoded = threshold.toRadixString(16).replaceFirst(RegExp(r'0+$'), '');
  return encoded.isEmpty ? '0' : encoded;
}

TraceState? _setOtelSubKey({
  required TraceState? traceState,
  required String subKey,
  required String? subValue,
}) {
  final members = <TraceStateMember>[...?traceState?.members];
  final otIndex = members.indexWhere((member) => member.key == 'ot');
  final otValue = _updateOtelValue(
    otIndex == -1 ? null : members[otIndex].value,
    subKey,
    subValue,
  );

  if (otValue == null) {
    if (otIndex != -1) {
      members.removeAt(otIndex);
    }
  } else if (otIndex == -1) {
    members.add(TraceStateMember(key: 'ot', value: otValue));
  } else {
    members[otIndex] = TraceStateMember(key: 'ot', value: otValue);
  }

  if (members.isEmpty) {
    return null;
  }

  return TraceState.tryFromMembers(members);
}

String? _readOtelSubKey(TraceState? traceState, String subKey) {
  final otValue = traceState?['ot']?.value;
  if (otValue == null) {
    return null;
  }

  for (final rawMember in otValue.split(';')) {
    final member = rawMember.trim();
    if (member.isEmpty) {
      continue;
    }

    final separatorIndex = member.indexOf(':');
    if (separatorIndex <= 0 || separatorIndex == member.length - 1) {
      continue;
    }

    if (member.substring(0, separatorIndex) == subKey) {
      return member.substring(separatorIndex + 1);
    }
  }

  return null;
}

String? _updateOtelValue(String? rawValue, String subKey, String? subValue) {
  final members = <String>[];
  var replaced = false;

  for (final rawMember in (rawValue ?? '').split(';')) {
    final member = rawMember.trim();
    if (member.isEmpty) {
      continue;
    }

    final separatorIndex = member.indexOf(':');
    if (separatorIndex <= 0 || separatorIndex == member.length - 1) {
      continue;
    }

    final key = member.substring(0, separatorIndex);
    if (key == subKey) {
      if (subValue != null) {
        members.add('$subKey:$subValue');
      }
      replaced = true;
      continue;
    }

    members.add(member);
  }

  if (!replaced && subValue != null) {
    members.add('$subKey:$subValue');
  }

  if (members.isEmpty) {
    return null;
  }

  return members.join(';');
}

bool _isLowerHex(String value) {
  for (final codeUnit in value.codeUnits) {
    final isDigit = codeUnit >= 0x30 && codeUnit <= 0x39;
    final isLowerHex = codeUnit >= 0x61 && codeUnit <= 0x66;
    if (!isDigit && !isLowerHex) {
      return false;
    }
  }

  return true;
}

const int _maxThreshold = 0x100000000000000;
