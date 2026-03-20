# Changelog

## 0.0.1-alpha.1

- Initial alpha release with Dio interceptor tracing and propagation.
- Added request and response body size telemetry.
- Added response content type and redirect resend count attributes.
- Added OpenTelemetry-aligned client status mapping for `4xx` and `5xx` responses.
- Added opt-in request and response header capture with redaction for sensitive headers.
- Added `http.request.method_original` support for non-standard methods.
- Expanded test coverage from 2 to 12 scenarios.
- Added a publish-ready example and a pub.dev-oriented README.