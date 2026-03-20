part of '../comon_otel_test.dart';

void defineHttpTransportTests() {
  group('http transport', () {
    test('default transport sends request body and reads response', () async {
      final transport = DefaultOtlpHttpTransport(
        client: _FakeHttpClient(
          handler: (request) async {
            expect(request.method, 'POST');
            expect(
              request.url.toString(),
              'https://collector.example/v1/traces',
            );
            expect(request.headers['content-type'], 'application/json');
            expect(utf8.decode(request.bodyBytes), '{"ok":true}');
            return http.Response(
              '{"partialSuccess":{}}',
              200,
              headers: <String, String>{'retry-after': '3'},
            );
          },
        ),
      );

      final response = await transport.postJson(
        OtlpHttpRequest(
          uri: Uri.parse('https://collector.example/v1/traces'),
          body: '{"ok":true}',
          headers: <String, String>{'content-type': 'application/json'},
          timeout: Duration(seconds: 1),
        ),
      );

      expect(response.statusCode, 200);
      expect(response.body, '{"partialSuccess":{}}');
      expect(response.headers['retry-after'], '3');
      await transport.shutdown();
    });

    test('gzip request body is encoded without dart:io gzip', () {
      final request = OtlpHttpRequest(
        uri: Uri.parse('https://collector.example/v1/logs'),
        body: '{"compressed":true}',
        headers: <String, String>{},
        timeout: Duration(seconds: 1),
        compression: OtlpCompression.gzip,
      );

      final decoded = utf8.decode(gzip.decode(request.bodyBytes));
      expect(decoded, '{"compressed":true}');
    });
  });
}

final class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient({required this.handler});

  final Future<http.Response> Function(http.Request request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final typedRequest = request as http.Request;
    final response = await handler(typedRequest);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: typedRequest,
    );
  }
}
