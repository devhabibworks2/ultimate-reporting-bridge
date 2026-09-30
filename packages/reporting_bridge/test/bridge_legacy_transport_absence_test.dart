import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('core Bridge contains no legacy Presenter discovery transport', () {
    final sources = <String>[
      File('lib/src/bridge_presenter_server.dart').readAsStringSync(),
      File('lib/src/bridge_template_sync.dart').readAsStringSync(),
      File('lib/src/bridge_client.dart').readAsStringSync(),
    ].join('\n');

    expect(sources, isNot(contains('presenter/systems')));
    expect(sources, isNot(contains("_listPath = 'presenter/templates'")));
    expect(sources, isNot(contains('_detailPathPrefix')));
    expect(sources, isNot(contains('fetchSystems')));
    expect(sources, isNot(contains('syncTemplatesToCache')));
    expect(
      sources,
      isNot(contains("@Deprecated('Use systemCode.') int? systemId")),
    );
  });

  test('Bridge header API has no legacy discovery or numeric selector', () {
    final source = File('lib/src/bridge_headers.dart').readAsStringSync();

    expect(source, isNot(contains('fetchSystems')));
    expect(source, isNot(contains('final int? systemId')));
  });
}
