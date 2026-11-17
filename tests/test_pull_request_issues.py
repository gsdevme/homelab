"""Checks on the hook that asks for the project-manager agent.

Run with:  python3 -m unittest discover tests
"""

import importlib.util
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("pull_request_issues", ROOT / ".claude/hooks/pull-request-issues.py")
hook = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(hook)

URL = "https://github.com/owner/homelab/pull/50"


def call(command, stdout="", **extra):
    """A PostToolUse tool call as the hook receives it."""
    return {"tool_input": {"command": command}, "tool_response": {"stdout": stdout, "stderr": ""}, **extra}


def never(target, cwd):
    """Stands in for GitHub where the hook must not need to ask."""
    raise AssertionError("GitHub was asked")


class OpenedTest(unittest.TestCase):
    def says_opened(self, command):
        text = hook.message(call(command, URL + "\n"), merged=never)
        self.assertIsNotNone(text, command)
        self.assertIn("just opened: " + URL, text)

    def test_each_way_of_running_create_is_seen(self):
        for command in (
            "gh pr create --title x",
            "cd /x && git push -q && gh pr create --fill",
            "GH_TOKEN=abc gh pr create --fill",
            "N=$(gh pr create --fill) && echo $N",
            "url=`gh pr create --fill`; echo $url",
            "if gh pr create --fill; then echo ok; fi",
            "{ gh pr create --fill; }",
            "/opt/homebrew/bin/gh pr create --fill",
            "gh -R owner/homelab pr create --fill",
            "gh pr create --body-file - <<'EOF'\nbody\nEOF",
            "cat <<EOF | gh pr create --body-file -\nbody\nEOF",
        ):
            self.says_opened(command)

    def test_create_that_printed_no_url_is_not_an_opened_pull_request(self):
        self.assertIsNone(hook.message(call("gh pr create --fill", ""), merged=never))

    def test_help_is_not_an_opened_pull_request(self):
        self.assertIsNone(hook.message(call("gh pr create --help", URL), merged=never))

    def test_a_mention_is_not_an_opened_pull_request(self):
        for command in (
            "echo 'run gh pr create later'",
            "gh pr edit 50 --body \"$(cat <<'EOF'\ngh pr create\nEOF\n)\"",
            "python3 - <<'EOF'\nfired after\ngh pr create --fill\nEOF\ngh pr edit 50 --body-file x",
            "gh pr view 50",
        ):
            self.assertIsNone(hook.message(call(command, URL), merged=never), command)


class MergedTest(unittest.TestCase):
    def test_merge_by_number_is_confirmed_with_github(self):
        asked = []

        def merged(target, cwd):
            asked.append((target, cwd))
            return [URL]

        text = hook.message(call("gh pr merge 50 --rebase", cwd="/repo"), merged=merged)
        self.assertEqual(asked, [("50", "/repo")])
        self.assertIn("Just merged: " + URL, text)

    def test_the_number_is_found_wherever_it_is(self):
        for command, number in (
            ("gh pr merge 50", "50"),
            ("gh pr merge --squash --delete-branch 50", "50"),
            ("gh pr merge " + URL + " --squash", "50"),
            ("gh pr merge 2>&1 | tail -3", None),
            ("gh pr merge --rebase", None),
            ("for n in 1 2; do gh pr merge $n; done", None),
        ):
            verb, arguments = hook.invocations(command)[0]
            self.assertEqual((verb, hook.merge_target(arguments)), ("merge", number), command)

    def test_nothing_is_said_when_github_says_it_did_not_merge(self):
        for command in ("gh pr merge 50 --auto --squash", "gh pr merge 50 || echo failed"):
            self.assertIsNone(hook.message(call(command), merged=lambda target, cwd: []), command)

    def test_help_does_not_ask_github(self):
        self.assertIsNone(hook.message(call("gh pr merge --help"), merged=never))

    def test_a_mention_is_not_a_merge(self):
        for command in (
            "gh pr edit 50 --body 'the hook (gh pr merge was missed) is fixed'",
            "gh pr comment 50 --body 'run tests then gh pr merge 50'",
            "gh pr edit 50 --body \"$(cat <<'EOF'\ntext\ngh pr merge 50\nEOF\n)\"",
        ):
            self.assertIsNone(hook.message(call(command, URL), merged=never), command)

    def test_an_unconfirmed_merge_says_so(self):
        text = hook.message(call("gh pr merge 50"), merged=lambda target, cwd: None)
        self.assertIn("could not be asked", text)
        self.assertIn("#50", text)

    def test_several_merges_in_one_command_are_reported_once(self):
        text = hook.message(call("for n in 1 2; do gh pr merge $n; done"), merged=lambda target, cwd: [URL])
        self.assertEqual(text.count("Just merged"), 1)


class WhoRanItTest(unittest.TestCase):
    def test_the_project_manager_is_not_asked_for_itself(self):
        mine = call("gh pr merge 50", agent_type="project-manager", agent_id="a1")
        self.assertIsNone(hook.message(mine, merged=never))

    def test_another_subagent_is_told_to_pass_it_on(self):
        text = hook.message(call("gh pr create --fill", URL, agent_type="general-purpose", agent_id="a1"), merged=never)
        self.assertIn("subagent", text)

    def test_the_main_session_is_not_told_it_is_a_subagent(self):
        self.assertNotIn("subagent", hook.message(call("gh pr create --fill", URL), merged=never))


class AskingGitHubTest(unittest.TestCase):
    NOW = datetime(2026, 11, 17, 12, 0, tzinfo=timezone.utc)

    def test_a_numbered_pull_request_counts_only_when_merged(self):
        with mock.patch.object(hook, "gh_json", return_value={"state": "MERGED", "url": URL}):
            self.assertEqual(hook.merged("50", None), [URL])
        with mock.patch.object(hook, "gh_json", return_value={"state": "OPEN", "url": URL}):
            self.assertEqual(hook.merged("50", None), [])

    def test_without_a_number_only_recent_merges_count(self):
        listed = [
            {"url": URL, "mergedAt": "2026-11-17T11:57:00Z"},
            {"url": URL + "1", "mergedAt": "2026-11-17T09:00:00Z"},
        ]
        with mock.patch.object(hook, "gh_json", return_value=listed):
            self.assertEqual(hook.merged(None, None, now=self.NOW), [URL])

    def test_a_failure_to_ask_is_not_an_answer(self):
        with mock.patch.object(hook, "gh_json", side_effect=OSError("no gh")):
            self.assertIsNone(hook.merged("50", None))


if __name__ == "__main__":
    unittest.main()
