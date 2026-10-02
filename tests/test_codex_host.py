"""Helper regressions use a fake server; these unit tests are not host evidence."""
import copy
import hashlib
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import verify_codex_host as host


class CodexHostTests(unittest.TestCase):
    def test_sanitization_preserves_protocol_except_paths_and_host_ids(self):
        source = {'path': '/tmp/example/project/SKILL.md', 'serverName': 'host-name',
                  'installationId': 'temporary-id', 'enabled': True,
                  'result': [{'name': 'tk-luau-roblox'}]}
        result = host.sanitized(source, Path('/tmp/example'))
        self.assertEqual(result['path'], '<TEMP>/project/SKILL.md')
        self.assertEqual(result['serverName'], '<REDACTED_HOST_IDENTIFIER>')
        self.assertEqual(result['installationId'], '<REDACTED_HOST_IDENTIFIER>')
        self.assertEqual(result['result'], source['result'])
        self.assertIs(result['enabled'], True)

    def test_fingerprint_matches_release_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / 'SKILL.md'
            file.write_bytes(b'content')
            self.assertEqual(host.fingerprint([(file, Path('SKILL.md'))]),
                             hashlib.sha256(b'SKILL.md\0content\0').hexdigest())

    def test_discovery_requires_exact_enabled_repo_skill_and_clean_response(self):
        project = Path('/tmp/project')
        install = project / '.agents/skills/tk-luau-roblox'
        valid = {'error': None, 'skills_result': {'data': [{
            'cwd': str(project), 'errors': [], 'skills': [{
                'name': host.SKILL_NAME, 'path': str(install / 'SKILL.md'),
                'scope': 'repo', 'enabled': True}]}]}}
        self.assertTrue(host.discovery_passed(valid, project, install))
        for field, value in [('enabled', False), ('scope', 'user'),
                             ('path', '/somewhere/else/SKILL.md'), ('name', 'other')]:
            wrong = copy.deepcopy(valid)
            wrong['skills_result']['data'][0]['skills'][0][field] = value
            self.assertFalse(host.discovery_passed(wrong, project, install), field)
        wrong = copy.deepcopy(valid)
        wrong['skills_result']['data'][0]['errors'] = [{'message': 'invalid YAML'}]
        self.assertFalse(host.discovery_passed(wrong, project, install))
        wrong = copy.deepcopy(valid)
        wrong['skills_result']['data'][0]['skills'] *= 2
        self.assertFalse(host.discovery_passed(wrong, project, install))
        self.assertFalse(host.discovery_passed({'error': 'failed', 'skills_result': None},
                                              project, install))

    def fake_server(self, directory: str, response: str) -> Path:
        executable = Path(directory) / 'fake-codex'
        executable.write_text(f'#!{sys.executable}\nimport json, sys\n'
                              'for line in sys.stdin:\n'
                              '    request = json.loads(line)\n'
                              '    if request.get("method") == "initialize":\n'
                              '        print(json.dumps({"id": 1, "result": {}}), flush=True)\n'
                              '    elif request.get("method") == "skills/list":\n'
                              f'        print({response!r}, flush=True)\n')
        executable.chmod(0o700)
        return executable

    def test_protocol_uses_only_read_only_methods_and_exits_on_eof(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = self.fake_server(directory, '{"id": 2, "result": {"data": []}}')
            result = host.discover(str(executable), Path(directory), {}, 2)
            self.assertIsNone(result['error'])
            self.assertEqual(result['process_returncode'], 0)
            self.assertEqual([row['message']['method'] for row in result['transcript']
                              if row['direction'] == 'request'],
                             ['initialize', 'initialized', 'skills/list'])

    def test_rpc_error_is_preserved_and_does_not_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = self.fake_server(directory, '{"id": 2, "error": {"code": -1, "message": "test failure"}}')
            result = host.discover(str(executable), Path(directory), {}, 2)
            self.assertIn('test failure', result['error'])
            self.assertIsNone(result['skills_result'])
            self.assertEqual(result['process_returncode'], 0)


if __name__ == '__main__':
    unittest.main()
