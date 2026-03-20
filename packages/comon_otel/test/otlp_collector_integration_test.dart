@Tags(<String>['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:comon_otel/comon_otel.dart';
import 'package:test/test.dart';

part 'common/integration_test_support.dart';
part 'src/collector_roundtrip_integration_tests.dart';
part 'src/collector_override_retry_integration_tests.dart';

void main() {
  tearDown(() async {
    if (Otel.isInitialized) {
      await Otel.shutdown();
    }
  });

  group('collector integration', () {
    defineCollectorRoundTripIntegrationTests();
    defineCollectorOverrideAndRetryIntegrationTests();
  });
}
