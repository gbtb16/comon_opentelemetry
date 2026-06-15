# comon_otel_flutter

Flutter instrumentation for `comon_otel` with navigation, lifecycle, startup,
performance, interaction, and error telemetry.

## Features

- one-call installation with `ComonOtelFlutter.install(...)`
- route spans and screen-ready spans through `OtelNavigatorObserver`
- app lifecycle logs plus foreground/background duration metrics
- startup spans and first-interaction tracking
- frame timing, slow frame, jank frame, and UI stall telemetry
- Flutter framework and `PlatformDispatcher` error capture
- tap, form-submit, and widget-flow helpers through `OtelFlutterInteractions`
- breadcrumb capture that enriches later error telemetry

## Installation

```bash
flutter pub add comon_otel_flutter
```

## Quick Start

Initialize the core SDK first, then install the Flutter package and attach its navigator observer to `MaterialApp`.

```dart
import 'package:comon_otel/comon_otel.dart';
import 'package:comon_otel_flutter/comon_otel_flutter.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
	WidgetsFlutterBinding.ensureInitialized();

	await Otel.init(
		serviceName: 'shopping-app',
		exporter: OtelExporter.console,
	);

	final flutterTelemetry = ComonOtelFlutter.install();

	runApp(MyApp(flutterTelemetry: flutterTelemetry));
}

class MyApp extends StatelessWidget {
	const MyApp({super.key, required this.flutterTelemetry});

	final ComonOtelFlutterInstrumentation flutterTelemetry;

	@override
	Widget build(BuildContext context) {
		return MaterialApp(
			navigatorObservers: <NavigatorObserver>[
				if (flutterTelemetry.navigatorObserver != null)
					flutterTelemetry.navigatorObserver!,
			],
			home: const Scaffold(
				body: Center(child: Text('comon_otel_flutter')),
			),
		);
	}
}
```

## Mobile init recommendations

On Flutter mobile, environment variables do not reach the SDK, so enable
batching and periodic metric export explicitly:

    await Otel.init(
      serviceName: 'my-app',
      exporter: OtelExporter.otlpHttpJson,
      tracesEndpoint: 'https://collector.example.com/otel/http/v1/traces',
      // ...per-signal endpoints + auth headers...
      useBatchSpanProcessor: true,
      useBatchLogProcessor: true,
      usePeriodicMetricReader: true,
      metricExportInterval: const Duration(seconds: 60),
    );

Without `usePeriodicMetricReader: true`, metrics are only exported on
`forceFlush()` (e.g. on app background) and never on a timer.

## Configuration

`ComonOtelFlutterConfig` controls which signals are active and how they are
named.

Common options include:

- `captureFlutterErrors`
- `capturePlatformDispatcherErrors`
- `observeAppLifecycle`
- `trackNavigatorRoutes`
- `trackAppStartup`
- `trackScreenReady`
- `trackFrameTimings`
- `trackUiStalls`
- `trackBreadcrumbs`
- `routeSpanNamePrefix`
- `screenReadySpanNamePrefix`
- `slowFrameThreshold`
- `jankFrameThreshold`
- `uiStallThreshold`

Example configuration:

```dart
final flutterTelemetry = ComonOtelFlutter.install(
	config: const ComonOtelFlutterConfig(
		routeSpanNamePrefix: 'flutter.route',
		screenReadySpanNamePrefix: 'flutter.screen_ready',
		trackFrameTimings: true,
		trackUiStalls: true,
		breadcrumbCapacity: 30,
	),
);
```

## Navigation

`OtelNavigatorObserver` creates spans for route transitions and closes them when the route leaves the stack.

Recorded attributes currently include:

- `flutter.navigation.action`
- `flutter.route.name`
- `flutter.route.runtime_type`
- `flutter.previous_route.name`

The default span name format is `flutter.route <routeName>` and can be changed through `ComonOtelFlutterConfig`.

## Error Capture

`ComonOtelFlutter.install(...)` can wire both:

- `FlutterError.onError`
- `PlatformDispatcher.instance.onError`

Each captured error is recorded as:

- a span with an exception event
- an error log with exception attributes
- breadcrumb-enriched context from recent lifecycle, navigation, and UI signals

Existing error handlers are preserved and still invoked after telemetry is recorded.

## Performance

The package can emit:

- startup spans
- first-frame events
- foreground/background duration metrics
- frame duration, build duration, and raster duration metrics
- slow frame and jank frame counters
- UI stall duration and count metrics
- memory pressure count metrics

This is useful for correlating user-visible responsiveness with route changes,
errors, and interactions.

## Interactions

`OtelFlutterInteractions` provides opt-in helpers for UX telemetry without forcing custom widgets into your tree.

```dart
ElevatedButton(
	onPressed: OtelFlutterInteractions.wrapAsyncTap(
		targetName: 'checkout_button',
		onTap: () async {
			await OtelFlutterInteractions.traceFormSubmit(
				formName: 'checkout_form',
				action: () async {
					// submit order
				},
			);
		},
	),
	child: const Text('Checkout'),
)
```

Helpers currently cover:

- tap callbacks for buttons and gesture handlers
- async form submit spans
- widget-level opt-in tracing for expensive flows

## Platform Setup

There is currently no extra Android or iOS manifest setup required by the
package itself. Standard exporter or networking requirements still depend on how
you initialize `comon_otel` in your app.

## Example

The full Flutter example app lives under `example/`, and the minimal pub.dev
entrypoint is [example/comon_otel_flutter_example.dart](example/comon_otel_flutter_example.dart).

## Ecosystem

- [comon_otel](../comon_otel/README.md): core SDK with traces, metrics, logs, propagation, and exporters
- [comon_otel_dio](../comon_otel_dio/README.md): Dio client spans, propagation, and HTTP client attributes

## Roadmap

The implementation roadmap for this package lives in `IMPLEMENTATION_PLAN.md` and is intended to be the source of truth for the next iterations.

