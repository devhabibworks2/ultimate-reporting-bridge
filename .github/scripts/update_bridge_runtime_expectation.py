from pathlib import Path

path = Path('packages/reporting_bridge/test/bridge_runtime_test.dart')
text = path.read_text()
old = """        expect(wrongType.status, 'auto-selected');
        expect(wrongType.template?.id, '90');
"""
new = """        expect(wrongType.status, 'selection-required');
        expect(wrongType.template, isNull);
        expect(
          wrongType.errorCode,
          BridgeRuntimeErrorCodes.staleTemplateSelection,
        );
"""
count = text.count(old)
if count != 1:
    raise SystemExit(f'expected one legacy wrongType assertion block, found {count}')
path.write_text(text.replace(old, new, 1))
