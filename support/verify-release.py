#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise release preparation against real disposable Git remotes and a gh fixture."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
REQUIRED = ["slicer-release-assets", "slicer-linux-release", "slicer-native-release", "slicer-windows-release"]
GH_FIXTURE = r'''#!/usr/bin/env python3
import json, os, pathlib, subprocess, sys
path = pathlib.Path(os.environ['SLICER_RELEASE_FIXTURE'])
state = json.loads(path.read_text())
args = sys.argv[1:]
state['calls'].append(args)
path.write_text(json.dumps(state))
if args[0] == 'api':
    if state.get('api_error'):
        print('GitHub request failed', file=sys.stderr)
        sys.exit(1)
    endpoint = args[-1]
    if '/artifacts?' in endpoint:
        print(json.dumps({'artifacts': state.get('artifacts', [])}))
    else:
        head = subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
        for page in state.get('run_pages', [state.get('runs', [])]):
            runs = []
            for override in page:
                item = dict(id=42, head_sha=head, head_branch='main', path='.github/workflows/ci.yml',
                            head_repository={'full_name':'fixture/Slicer'}, event='push',
                            status='completed', conclusion='success', html_url='https://github.com/fixture/Slicer/actions/runs/42')
                item.update(override)
                runs.append(item)
            print(json.dumps({'workflow_runs': runs}))
elif args[:2] != ['workflow', 'run']:
    sys.exit(99)
'''


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="slicer release ")
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        self.repo = self.work / "source with spaces"
        self.repo.mkdir()
        self.remote = self.work / "origin.git"
        self.git_external("init", "--bare", "-q", "-b", "main", str(self.remote))
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "Release Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        (self.repo / "support").mkdir()
        (self.repo / "support/VERSION").write_text("0.0.1\n")
        (self.repo / "README").write_text("Project\n")
        self.git("add", ".")
        self.git("commit", "-q", "-m", "Fixture source")
        self.git("remote", "add", "origin", str(self.remote))
        self.git("push", "-q", "-u", "origin", "main")
        self.original = self.git("rev-parse", "HEAD")
        self.state_path = self.work / "github.json"
        self.set_state()
        tools = self.work / "tools"
        tools.mkdir()
        gh = tools / "gh"
        gh.write_text(GH_FIXTURE)
        gh.chmod(0o755)
        self.environment = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"],
                                GITHUB_REPOSITORY="fixture/Slicer", SLICER_RELEASE_FIXTURE=str(self.state_path),
                                GITHUB_STEP_SUMMARY=str(self.work / "summary.md"))

    def git_external(self, *args):
        return subprocess.check_output(["git", *args], text=True, stderr=subprocess.PIPE).strip()

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args], text=True, stderr=subprocess.PIPE).strip()

    def set_state(self, **values):
        self.state_path.write_text(json.dumps(dict(calls=[], **values)))

    def calls(self):
        return json.loads(self.state_path.read_text())["calls"]

    def invoke(self, *args, ok=True):
        result = subprocess.run([sys.executable, str(ROOT / "support/release.py"), *args],
                                cwd=self.repo, env=self.environment, text=True, capture_output=True)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(self.git("status", "--porcelain"), "")
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def tag(self, version):
        self.git("tag", "v" + version)
        self.git("push", "-q", "origin", "v" + version)

    def requested(self):
        return [call for call in self.calls() if call[:2] == ["workflow", "run"]]

    def assert_build_requested(self):
        self.assertEqual(self.requested(), [["workflow", "run", "ci.yml", "--repo", "fixture/Slicer", "--ref", "main",
                                            "-f", "platform=all", "-f", "publish_release=true"]])

    def test_unpublished_version_is_retained_and_full_build_requested(self):
        self.invoke()
        self.assertEqual(self.git("rev-parse", "HEAD"), self.original)
        self.assert_build_requested()

    def test_numbering_skips_existing_tags_and_dispatches_after_push(self):
        for version in ("0.0.1", "0.0.2", "2.9.6"):
            self.tag(version)
        self.invoke()
        self.assertEqual((self.repo / "support/VERSION").read_text(), "0.0.3\n")
        head = self.git("rev-parse", "HEAD")
        self.assertNotEqual(head, self.original)
        self.assertEqual(self.git_external("--git-dir", str(self.remote), "rev-parse", "main"), head)
        self.assertEqual(self.git_external("--git-dir", str(self.remote), "rev-parse", "v0.0.1"), self.original)
        self.assert_build_requested()

    def test_explicit_version(self):
        self.invoke("--version", "0.1.0")
        self.assertEqual((self.repo / "support/VERSION").read_text(), "0.1.0\n")
        self.assert_build_requested()

    def test_active_build_is_reused_without_duplicate_dispatch(self):
        self.set_state(runs=[{"status": "in_progress", "conclusion": None}])
        result = self.invoke()
        self.assertIn("already running", result.stdout)
        self.assertEqual(self.requested(), [])

    def test_release_requested_manual_build_can_be_reused(self):
        self.set_state(runs=[{"event": "workflow_dispatch", "display_title": "Release Slicer / all / main",
                              "status": "queued", "conclusion": None}])
        self.invoke()
        self.assertEqual(self.requested(), [])

    def test_successful_build_with_all_files_is_published_without_rebuilding(self):
        self.set_state(runs=[{}], artifacts=[{"name": name, "expired": False} for name in REQUIRED])
        self.invoke()
        self.assertEqual(self.requested(), [["workflow", "run", "release.yml", "--repo", "fixture/Slicer",
                                            "--ref", "main", "-f", "qualified_run_id=42"]])

    def test_completed_manual_full_verification_can_be_published_on_request(self):
        self.set_state(runs=[{"event": "workflow_dispatch", "display_title": "Verify Slicer / all / main"}],
                       artifacts=[{"name": name, "expired": False} for name in REQUIRED])
        self.invoke()
        self.assertEqual(self.requested()[0][2], "release.yml")

    def test_missing_or_expired_files_require_a_new_build(self):
        for missing in (True, False):
            with self.subTest(missing=missing):
                artifacts = [{"name": name, "expired": False} for name in REQUIRED]
                if missing:
                    artifacts.pop()
                else:
                    artifacts[0]["expired"] = True
                self.set_state(runs=[{}], artifacts=artifacts)
                self.invoke()
                self.assert_build_requested()

    def test_other_sources_and_partial_manual_runs_cannot_publish(self):
        self.set_state(runs=[
            {"head_sha": "0" * 40}, {"head_branch": "other"},
            {"head_repository": {"full_name": "other/Slicer"}},
            {"path": ".github/workflows/other.yml"},
            {"event": "workflow_dispatch", "display_title": "Verify Slicer / all / main", "status": "in_progress", "conclusion": None},
            {"event": "workflow_dispatch", "display_title": "Release Slicer / windows / main"},
        ], artifacts=[{"name": name, "expired": False} for name in REQUIRED])
        self.invoke()
        self.assert_build_requested()

    def test_pagination_finds_an_active_run_on_a_later_page(self):
        self.set_state(run_pages=[[{"head_sha": "0" * 40}], [{"status": "in_progress"}]])
        self.invoke()
        self.assertEqual(self.requested(), [])

    def test_failed_or_cancelled_runs_cannot_publish_saved_files(self):
        for conclusion in ("failure", "cancelled"):
            with self.subTest(conclusion=conclusion):
                self.set_state(runs=[{"conclusion": conclusion}],
                               artifacts=[{"name": name, "expired": False} for name in REQUIRED])
                self.invoke()
                self.assert_build_requested()

    def test_retry_keeps_prepared_version_after_github_failure(self):
        self.tag("0.0.1")
        self.set_state(api_error=True)
        self.invoke(ok=False)
        prepared = self.git("rev-parse", "HEAD")
        self.assertEqual((self.repo / "support/VERSION").read_text(), "0.0.2\n")
        self.assertEqual(self.requested(), [])
        self.set_state()
        self.invoke()
        self.assertEqual(self.git("rev-parse", "HEAD"), prepared)
        self.assert_build_requested()

    def test_dry_run_makes_no_changes_or_github_requests(self):
        self.tag("0.0.1")
        self.invoke("--dry-run")
        self.assertEqual(self.git("rev-parse", "HEAD"), self.original)
        self.assertEqual(self.calls(), [])

    def test_dirty_checkout_is_preserved(self):
        (self.repo / "README").write_text("User changes\n")
        self.invoke(ok=False)
        self.assertEqual((self.repo / "README").read_text(), "User changes\n")
        self.assertEqual(self.git("rev-parse", "HEAD"), self.original)
        self.assertEqual(self.calls(), [])

    def test_local_only_commits_are_preserved(self):
        (self.repo / "README").write_text("Local work\n")
        self.git("commit", "-q", "-a", "-m", "Local work")
        local = self.git("rev-parse", "HEAD")
        self.invoke(ok=False)
        self.assertEqual(self.git("rev-parse", "HEAD"), local)
        self.assertEqual(self.git_external("--git-dir", str(self.remote), "rev-parse", "main"), self.original)

    def test_non_main_checkout_is_refused(self):
        self.git("checkout", "-q", "-b", "fixture-branch")
        self.invoke(ok=False)
        self.assertEqual(self.git("branch", "--show-current"), "fixture-branch")
        self.assertEqual(self.calls(), [])

    def test_published_backward_and_invalid_versions_are_refused(self):
        self.tag("0.0.1")
        for version in ("0.0.1", "0.0.0", "0.0.2; touch injected", "01.0.0"):
            with self.subTest(version=version):
                self.invoke("--version", version, ok=False)
                self.assertEqual(self.git("rev-parse", "HEAD"), self.original)
                self.assertEqual((self.repo / "support/VERSION").read_text(), "0.0.1\n")
                self.assertEqual(self.calls(), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
