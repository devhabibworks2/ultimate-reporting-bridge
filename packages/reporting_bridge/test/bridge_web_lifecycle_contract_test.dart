import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  test('parses Presenter capability and render lifecycle events', () {
    final connected = PresenterWebLifecycleEvent.tryParse(<String, dynamic>{
      'channel': bridgeWebMessageChannel,
      'method': BridgeWebMethods.presenterLifecycle,
      'contractVersion': BridgeContract.payloadVersion,
      'event': 'onPresenterReady',
      'payload': <String, dynamic>{
        'features': <String>['renderLifecycle', 'chunkedPdfExport'],
      },
    });
    final ready = PresenterWebLifecycleEvent.tryParse(<String, dynamic>{
      'channel': bridgeWebMessageChannel,
      'method': BridgeWebMethods.presenterLifecycle,
      'contractVersion': BridgeContract.payloadVersion,
      'event': 'onRenderCompleted',
      'payload': <String, dynamic>{'sessionId': 'session-1'},
    });

    expect(connected, isNotNull);
    expect(connected!.state, PresenterWebLifecycleState.connected);
    expect(connected.contractVersion, BridgeContract.payloadVersion);
    expect(ready, isNotNull);
    expect(ready!.state, PresenterWebLifecycleState.ready);
    expect(ready.contractVersion, BridgeContract.payloadVersion);
    expect(ready.sessionId, 'session-1');
  });

  test('rejects lifecycle messages without a positive contract version', () {
    expect(
      PresenterWebLifecycleEvent.tryParse(<String, dynamic>{
        'channel': bridgeWebMessageChannel,
        'method': BridgeWebMethods.presenterLifecycle,
        'event': 'onRenderCompleted',
        'payload': <String, dynamic>{'sessionId': 'session-1'},
      }),
      isNull,
    );
    expect(
      PresenterWebLifecycleEvent.tryParse(<String, dynamic>{
        'channel': bridgeWebMessageChannel,
        'method': BridgeWebMethods.exportPdf,
      }),
      isNull,
    );
  });
}
