#!/usr/bin/env python3
"""Offline behavior checks. curl is replaced; no Plain calls or credentials are used."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / 'skills/plain-configuration/scripts/plain-config.sh'
FAKE_CURL = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
payload = json.loads(args[args.index('-d') + 1])
with open(os.environ['PLAIN_TEST_LOG'], 'a') as f:
    f.write(json.dumps(payload) + '\n')
q, v = payload['query'], payload['variables']
mode = os.environ.get('PLAIN_TEST_MODE', '')
if mode == 'transport':
    print('{"message":"upstream unavailable"}'); sys.exit(22)
if mode == 'invalid':
    print('<html>upstream unavailable</html>'); sys.exit(0)
if mode == 'graphql' or (mode == 'hours-error' and 'businessHoursSlots' in q):
    print(json.dumps({'errors':[{'message':'permission denied'}]})); sys.exit(0)
if mode == 'mutation':
    print(json.dumps({'data':{'createSidekickCustomSkill':{'customSkill':None,'error':{'message':'invalid instructions','code':'validation_error'}}}})); sys.exit(0)
if 'labelTypes(' in q:
    cursor = v.get('after')
    if mode == 'page-two-error' and cursor:
        print(json.dumps({'errors':[{'message':'second page refused'}]})); sys.exit(0)
    edges = [{'node':{'id':'lt_second' if cursor else 'lt_first','name':'Engineering','type':'TEAM'}}]
    if mode == 'large':
        edges = [{'node':{'id':f'lt_{cursor}_{i}','name':'x'*500,'type':'TEAM'}} for i in range(200)]
    page = {'hasNextPage':not bool(cursor), 'endCursor':'page-2' if not cursor else None}
    if mode == 'stuck': page = {'hasNextPage':True, 'endCursor':'page-2'}
    print(json.dumps({'data':{'labelTypes':{'edges':edges,'pageInfo':page}}})); sys.exit(0)
if 'businessHoursSlots' in q:
    print(json.dumps({'data':{'businessHoursSlots':[{'weekday':'MONDAY','opensAt':'09:00','closesAt':'17:00'}]}})); sys.exit(0)
if 'createSidekickCustomSkill(' in q:
    print(json.dumps({'data':{'createSidekickCustomSkill':{'customSkill':{'id':'sk_1','name':'server-derived-name','isEnabled':True,**v['i']},'error':None}}})); sys.exit(0)
if 'updateSidekickCustomSkill(' in q:
    print(json.dumps({'data':{'updateSidekickCustomSkill':{'customSkill':{'id':'sk_1','name':'server-derived-name',**v['i']},'error':None}}})); sys.exit(0)
if 'createWorkflowStep(' in q:
    print(json.dumps({'data':{'createWorkflowStep':{'workflowStep':{'id':'step_1'},'error':None}}})); sys.exit(0)
if 'addLabelsToUser(' in q:
    print(json.dumps({'data':{'addLabelsToUser':{'user':{'id':v['i']['entityId']},'error':None}}})); sys.exit(0)
print(json.dumps({'data':{'myWorkspace':{'id':'ws_test','name':'Offline fixture'}}}))
'''


class CLIContract(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)
        curl = self.path / 'curl'
        curl.write_text(FAKE_CURL)
        curl.chmod(0o755)
        self.log = self.path / 'requests.jsonl'
        self.env = dict(os.environ, PATH=str(self.path) + os.pathsep + os.environ['PATH'],
                        PLAIN_API_KEY='offline-test-sentinel', PLAIN_TEST_LOG=str(self.log))
        self.instructions = self.path / 'instructions.md'
        self.instructions.write_text('Check "related issues".\nUse /child-skill.\nDo not send $KEY or `secrets`.\n')

    def run_cli(self, *args, mode='', key=True):
        env = dict(self.env, PLAIN_TEST_MODE=mode)
        if not key:
            env.pop('PLAIN_API_KEY', None)
        result = subprocess.run(['bash', str(CLI), *args], env=env, text=True,
                                capture_output=True, timeout=10)
        self.assertNotIn('offline-test-sentinel', result.stdout + result.stderr)
        return result

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def create(self, **kw):
        return self.run_cli('skill', 'create', '--display-name', 'Bug investigation',
                            '--description', 'Investigate a failure.', '--instructions-file',
                            str(self.instructions), **kw)

    def test_help_and_payload_need_no_key_or_api(self):
        self.assertEqual(self.run_cli('help', key=False).returncode, 0)
        p = self.run_cli('payload', 'assign-team', 'lt_team', key=False)
        self.assertEqual(json.loads(p.stdout)['teamId'], 'lt_team')
        self.assertEqual(self.calls(), [])

    def test_skill_create_preserves_body_and_server_name(self):
        p = self.create()
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(self.calls()[0]['variables']['i']['instructions'], self.instructions.read_text())
        self.assertNotIn('name', self.calls()[0]['variables']['i'])
        self.assertEqual(json.loads(p.stdout)['data']['createSidekickCustomSkill']['customSkill']['name'], 'server-derived-name')

    def test_update_enablement_does_not_replace_body(self):
        p = self.run_cli('skill', 'update', '--id', 'sk_1', '--disable')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(self.calls()[0]['variables']['i'], {'customSkillId':'sk_1','isEnabled':False})

    def test_errors_fail_without_retries(self):
        for mode in ['transport', 'invalid', 'graphql', 'mutation']:
            with self.subTest(mode=mode):
                before = len(self.calls())
                p = self.create(mode=mode)
                self.assertNotEqual(p.returncode, 0)
                self.assertEqual(len(self.calls()), before + 1)

    def test_team_membership_uses_user_and_team_ids(self):
        p = self.run_cli('team','add-member','--team','lt_team','--user','u_jane')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(self.calls()[0]['variables']['i'], {'entityId':'u_jane','labelTypeIds':['lt_team']})

    def test_team_inventory_includes_later_pages(self):
        p = self.run_cli('teams')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual([x['id'] for x in json.loads(p.stdout)['data']['teams']], ['lt_first','lt_second'])
        self.assertEqual(self.calls()[1]['variables']['after'], 'page-2')

    def test_inventory_can_exceed_shell_argument_limit(self):
        p = self.run_cli('teams', mode='large')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(len(json.loads(p.stdout)['data']['teams']), 400)

    def test_partial_or_stuck_inventory_is_not_success(self):
        for mode in ['page-two-error','stuck']:
            with self.subTest(mode=mode):
                p = self.run_cli('label','list', mode=mode)
                self.assertNotEqual(p.returncode, 0)

    def test_hours_read_failure_or_existing_slots_prevent_mutation(self):
        for mode in ['', 'hours-error']:
            with self.subTest(mode=mode):
                p = self.run_cli('hours','set','--timezone','Europe/London',mode=mode)
                self.assertNotEqual(p.returncode, 0)
                self.assertTrue(all('mutation' not in x['query'] for x in self.calls()))

    def test_switch_ignores_whitespace_lines_consistently(self):
        prompts = self.path / 'prompts.txt'
        prompts.write_text('Match if broken.\n   \nMatch if billing.\n\n')
        p = self.run_cli('step','switch','--workflow','wf_1','--prompts',str(prompts),
                         '--transitions','step_bug,step_billing,step_fallback')
        self.assertEqual(p.returncode, 0, p.stderr)
        i = self.calls()[0]['variables']['i']
        self.assertEqual(len(json.loads(i['payload'])['conditions']),2)
        self.assertEqual(len(i['transitions']),3)

    def test_switch_rejects_missing_fallback(self):
        p = self.run_cli('step','switch','--workflow','wf_1','--prompts',str(self.instructions),
                         '--transitions','step_bug')
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_action_payload_file_preserves_json(self):
        payload = {'version':1,'type':'apply_labels','labelTypeIds':['lt_actual']}
        path = self.path / 'action.json'; path.write_text(json.dumps(payload))
        p = self.run_cli('step','action','--workflow','wf_1','--payload-file',str(path))
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(json.loads(self.calls()[0]['variables']['i']['payload']), payload)

    def test_invalid_payload_and_unknown_option_do_not_write(self):
        self.assertNotEqual(self.run_cli('step','action','--workflow','wf_1','--payload','[]').returncode,0)
        self.assertNotEqual(self.run_cli('label','create','--name','Bug','--typo','x').returncode,0)
        self.assertEqual(self.calls(), [])


class RetargetContract(unittest.TestCase):
    def test_relocation_preserves_other_repositories_and_nested_refs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'scripts').mkdir()
            shutil.copy(ROOT/'scripts/retarget.sh', root/'scripts/retarget.sh')
            (root/'README.md').write_text(
                'https://raw.githubusercontent.com/jungfreud/plain-skills/main/skills/plain-onboarding/SKILL.md\n'
                'https://github.com/jungfreud/plain-skills/issues\n'
                'npx skills add jungfreud/plain-skills\n'
                'npx skills add team-plain/plain-support\n'
                'https://github.com/team-plain/plain-support\n')
            subprocess.run(['git','init','-q',str(root)],check=True)
            subprocess.run(['git','add','.'],cwd=root,check=True)
            for target, ref in [('team-plain/setup','review/next'),('team-plain/final','main')]:
                p=subprocess.run(['bash','scripts/retarget.sh',target,ref],cwd=root,capture_output=True,text=True)
                self.assertEqual(p.returncode,0,p.stderr)
            text=(root/'README.md').read_text()
            self.assertIn('team-plain/final/main/skills/plain-onboarding',text)
            self.assertIn('https://github.com/team-plain/plain-support',text)
            self.assertIn('npx skills add team-plain/plain-support',text)
            self.assertNotIn('jungfreud/plain-skills',text)


if __name__ == '__main__':
    unittest.main(verbosity=2)
