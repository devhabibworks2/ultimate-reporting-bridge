from pathlib import Path
import yaml
root=Path(__file__).resolve().parents[1]
jobs=yaml.safe_load((root/'.github/workflows/ci.yml').read_text())['jobs']
assert 'publish-authority' in jobs, 'missing publish-authority job'
job=jobs['publish-authority']
assert set(job['needs'])=={'reporting-bridge','reporting-bridge-flutter','minimal-host'}
assert job.get('permissions',{}).get('contents')=='write'
assert "github.event_name == 'push'" in job.get('if','')
run='\n'.join(str(s.get('run','')) for s in job.get('steps',[]))
for token in ('ci-authority','authority/','GITHUB_SHA','GITHUB_RUN_ID','reporting-bridge','reporting-bridge-flutter','minimal-host'):
    assert token in run, token
print('bridge_ci_authority_publisher_contract=PASS')
