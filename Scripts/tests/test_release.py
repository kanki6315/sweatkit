"""Exercise release boundaries without signing, uploading or touching devices."""
import importlib.util
import io
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('smoke', ROOT / 'Scripts/release_smoke.py')
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


class SmokeTests(unittest.TestCase):
    def test_lost_lease_stops_running_command(self):
        lease = Mock()
        lease.poll.side_effect = [None, 14]
        process = Mock()
        process.wait.side_effect = [subprocess.TimeoutExpired('install', .2), 0]
        process.poll.return_value = None
        with patch.object(smoke.subprocess, 'Popen', return_value=process):
            with self.assertRaisesRegex(RuntimeError, 'lease ended'):
                smoke.run_leased(lease, ['simlock', 'simctl', 'install'])
        process.terminate.assert_called_once()

    def test_install_failure_releases_lease(self):
        lease = Mock()
        lease.stdout = io.StringIO('{"lease":{"id":"ours"},"device":{"address":"device"}}\n')
        lease.poll.return_value = None
        with tempfile.TemporaryDirectory() as folder:
            with patch('sys.argv', ['smoke', '--app', folder, '--bundle-id', 'example']), \
                 patch.object(smoke.subprocess, 'run'), \
                 patch.object(smoke.subprocess, 'Popen', return_value=lease), \
                 patch.object(smoke, 'run_leased', side_effect=[None, RuntimeError('install failed')]) as run:
                with self.assertRaisesRegex(RuntimeError, 'install failed'):
                    smoke.main()
        lease.terminate.assert_called_once()
        self.assertEqual(run.call_count, 2)
        self.assertEqual(run.call_args.args[1][:4], ['simlock', 'simctl', '--lease', 'ours'])


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        shutil.copy(ROOT / 'release.sh', self.root)
        shutil.copy(ROOT / 'project.yml', self.root)
        (self.root / 'bin').mkdir()
        self.log = self.root / 'commands'
        for name, body in {
            'git': 'case "$1" in status) ;; rev-parse) [ "$2" != "--verify" ] || exit 1; echo abc123 ;; tag) echo tag >> "$COMMAND_LOG" ;; esac',
            'xcodegen': 'exit 0',
            'xcodebuild': 'echo "$*" >> "$COMMAND_LOG"\nexit "${BUILD_EXIT:-0}"',
        }.items():
            path = self.root / 'bin' / name
            path.write_text('#!/bin/sh\n' + body + '\n')
            path.chmod(0o755)
        self.env = {k: v for k, v in os.environ.items() if not k.startswith('ASC_')}
        self.env.update(PATH=f"{self.root / 'bin'}:{os.environ['PATH']}",
                        DEVELOPER_DIR=str(self.root), RELEASE_ENV_FILE=str(self.root / 'absent'),
                        COMMAND_LOG=str(self.log))

    def release(self, *args):
        return subprocess.run(['bash', str(self.root / 'release.sh'), '--skip-tests', *args],
                              env=self.env, text=True, capture_output=True)

    def test_export_does_not_upload_or_tag(self):
        result = self.release('--no-upload', '--build', '42')
        self.assertEqual(result.returncode, 0, result.stderr)
        options = plistlib.loads((self.root / 'build/release/0.1.0-42/ExportOptions.plist').read_bytes())
        self.assertEqual(options['destination'], 'export')
        self.assertNotIn('tag', self.log.read_text())
        self.assertIn('-exportArchive', self.log.read_text())
        self.assertNotEqual(self.release('--no-upload', '--build', '42').returncode, 0)

    def test_archive_failure_prevents_export_and_tag(self):
        self.env['BUILD_EXIT'] = '65'
        result = self.release('--build', '43')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('-exportArchive', self.log.read_text())
        self.assertNotIn('tag', self.log.read_text())

    def test_invalid_build_rejected_before_build(self):
        result = self.release('--build', '12345')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.log.exists())

    def test_upload_tags_only_after_success(self):
        result = self.release('--build', '44')
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = self.log.read_text().splitlines()
        self.assertIn('-exportArchive', lines[-2])
        self.assertEqual(lines[-1], 'tag')


if __name__ == '__main__':
    unittest.main()
