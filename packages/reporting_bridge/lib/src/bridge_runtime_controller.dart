import 'bridge_local_server.dart';
import 'bridge_runtime_session.dart';
import 'bridge_runtime_storage.dart';

class BridgeRuntimeController {
  BridgeRuntimeController({
    required this.runtimeStorage,
    required this.localServer,
  });

  final RuntimeSessionStorage runtimeStorage;
  final LocalPresenterServer localServer;
  LocalServerHandle? _localServerHandle;
  String? _activeSessionId;

  Future<RuntimeSession> prepareRuntimeSession(RuntimeSessionInput input) {
    return runtimeStorage.prepareRuntimeSession(input);
  }

  Future<LocalServerHandle> startLocalPresenterServer({
    required String sessionId,
    PortPolicy portPolicy = const PortPolicy(),
  }) async {
    await _stopActiveSession();
    try {
      final handle = await localServer.start(
        sessionId: sessionId,
        portPolicy: portPolicy,
      );
      _localServerHandle = handle;
      _activeSessionId = sessionId;
      return handle;
    } catch (_) {
      await runtimeStorage.deleteRuntimeSession(sessionId);
      rethrow;
    }
  }

  Future<void> disposeBridge() async {
    try {
      await _stopActiveSession();
    } finally {
      await localServer.stop();
    }
  }

  Future<void> _stopActiveSession() async {
    final handle = _localServerHandle;
    final sessionId = _activeSessionId;
    _localServerHandle = null;
    _activeSessionId = null;

    Object? failure;
    StackTrace? failureStackTrace;
    try {
      await handle?.stop();
    } catch (error, stackTrace) {
      failure = error;
      failureStackTrace = stackTrace;
    }

    if (sessionId != null) {
      try {
        await runtimeStorage.deleteRuntimeSession(sessionId);
      } catch (error, stackTrace) {
        failure ??= error;
        failureStackTrace ??= stackTrace;
      }
    }

    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStackTrace!);
    }
  }
}
