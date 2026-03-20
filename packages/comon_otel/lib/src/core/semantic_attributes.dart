/// Common semantic attribute keys reused across the SDK integrations.
final class SemanticAttributes {
  const SemanticAttributes._();

  /// Service name resource attribute.
  static const String serviceName = 'service.name';

  /// Service version resource attribute.
  static const String serviceVersion = 'service.version';

  /// Service namespace resource attribute.
  static const String serviceNamespace = 'service.namespace';

  /// Deployment environment resource attribute.
  static const String deploymentEnvironment = 'deployment.environment';

  /// HTTP request method attribute.
  static const String httpMethod = 'http.request.method';

  /// Original HTTP request method attribute for non-standard methods.
  static const String httpMethodOriginal = 'http.request.method_original';

  /// HTTP response status code attribute.
  static const String httpStatusCode = 'http.response.status_code';

  /// HTTP response content type attribute.
  static const String httpResponseContentType = 'http.response.content_type';

  /// HTTP resend count attribute used for redirects or retries.
  static const String httpResendCount = 'http.resend_count';

  /// Route template attribute for HTTP servers or clients.
  static const String httpRoute = 'http.route';

  /// Full request URL attribute.
  static const String httpUrl = 'url.full';

  /// HTTP request body size attribute.
  static const String httpRequestBodySize = 'http.request.body.size';

  /// HTTP response body size attribute.
  static const String httpResponseBodySize = 'http.response.body.size';

  /// Database system attribute.
  static const String dbSystem = 'db.system';

  /// Database namespace attribute.
  static const String dbName = 'db.namespace';

  /// Database operation name attribute.
  static const String dbOperation = 'db.operation.name';

  /// Database statement attribute.
  static const String dbStatement = 'db.statement';

  /// Database collection or table attribute.
  static const String dbTable = 'db.collection.name';

  /// RPC system attribute.
  static const String rpcSystem = 'rpc.system';

  /// RPC service attribute.
  static const String rpcService = 'rpc.service';

  /// RPC method attribute.
  static const String rpcMethod = 'rpc.method';

  /// Peer name or server address attribute.
  static const String netPeerName = 'server.address';

  /// Peer or server port attribute.
  static const String netPeerPort = 'server.port';

  /// Network protocol name attribute.
  static const String networkProtocolName = 'network.protocol.name';

  /// User identifier attribute.
  static const String userId = 'user.id';

  /// Tenant identifier attribute.
  static const String tenantId = 'tenant.id';

  /// Thread type attribute.
  static const String threadType = 'thread.type';

  /// Exception type attribute.
  static const String exceptionType = 'exception.type';

  /// Exception message attribute.
  static const String exceptionMessage = 'exception.message';

  /// Exception stacktrace attribute.
  static const String exceptionStacktrace = 'exception.stacktrace';

  /// Code function attribute.
  static const String codeFunction = 'code.function';

  /// Code namespace attribute.
  static const String codeNamespace = 'code.namespace';

  /// Flutter route attribute.
  static const String flutterRoute = 'flutter.route';

  /// Flutter widget attribute.
  static const String flutterWidget = 'flutter.widget';

  /// Flutter build duration attribute.
  static const String flutterBuildDuration = 'flutter.build.duration';

  /// Flutter frame duration attribute.
  static const String flutterFrameDuration = 'flutter.frame.duration';

  /// Application lifecycle state attribute.
  static const String appLifecycleState = 'app.lifecycle.state';
}
