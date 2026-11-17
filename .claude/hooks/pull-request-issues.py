#!/usr/bin/env python3
"""After a pull request is opened or merged, ask for the project-manager agent.

Runs from the PostToolUse hook on Bash in .claude/settings.json, which passes
the tool call as JSON on stdin. When the command opened a pull request
(`gh pr create`) or merged one (`gh pr merge`), it prints a hook result whose
additionalContext tells Claude to run the project-manager agent, so the
issues are checked against the pull request every time, not only when
someone remembers.

What counts:

- The command has to be run, not mentioned. Heredoc bodies and quoted
  strings are taken out before looking, so `gh pr merge` in a pull request
  description or a comment is not a merge.
- An opened pull request is one whose URL `gh pr create` printed.
- A merged pull request is one GitHub says is merged. `gh pr merge` prints
  nothing to go on, and `--auto`, `--help` and a failed merge all look the
  same from here, so the hook asks GitHub: for the number or URL given, or
  failing that for whatever was merged in the last few minutes. If GitHub
  cannot be asked, it says the merge is unconfirmed and leaves it to the
  agent.

It says nothing for any other command and for the project-manager agent's
own commands. It always exits 0: a hook must never get in the way of the
work.

It is run with whatever `python3` is on the PATH: this repo has no Python
environment of its own, and the hook must not build one on every shell
command. Keep it to the standard library and to syntax Python 3.9 accepts.
"""

import json
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone

AGENT = "project-manager"
RECENT = timedelta(minutes=10)

PR_URL = re.compile(r"https://github\.com/[^\s/]+/[^\s/]+/pull/(\d+)")
HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1([^\n]*)\n.*?\n[ \t]*\2(?=\n|$)", re.S)
QUOTED = re.compile(r"'[^']*'|\"(?:\\.|[^\"\\])*\"")
INVOCATION = re.compile(
    r"(?:^|[;&|({`\n]|\b(?:do|then|else|if|while|until)\s)\s*"
    r"(?:\w+=\S*\s+)*"
    r"(?:\S*/)?gh\s+(?:(?:-R|--repo)[=\s]\s*\S+\s+)?pr\s+(create|merge)\b"
    r"([^;&|\n)`]*)"
)

OPENED = (
    "A pull request was just opened: {prs}. Before you finish, run the {agent} agent on it: "
    "it works out which open issues the pull request resolves or moves on and links them "
    "in its description."
)
MERGED = (
    "Just merged: {prs}. Before you finish, run the {agent} agent on each: it brings the "
    "issues the pull request named in step with what was merged and reports any that can "
    "now be closed."
)
UNCONFIRMED = (
    "`gh pr merge` was run for {prs}, but GitHub could not be asked whether it merged. "
    "Check that it did; if so, run the {agent} agent on it before you finish."
)
SUBAGENT = (
    " You are running as a subagent: if you cannot run that agent yourself, say in your "
    "report that the main session must."
)


def invocations(command):
    """Each `gh pr create` or `gh pr merge` the command runs, as (verb, arguments).

    Heredoc bodies and quoted strings are removed first, keeping the rest of
    the line a heredoc starts on, so text that only mentions a command is
    not counted. Quoted arguments come back empty.
    """
    bare = QUOTED.sub('""', HEREDOC.sub(r"\3\n", command))
    return [(verb, arguments.split()) for verb, arguments in INVOCATION.findall(bare)]


def merge_target(arguments):
    """The pull request number a `gh pr merge` names, or None for the branch's own."""
    for argument in arguments:
        if argument.isdigit():
            return argument
        url = PR_URL.fullmatch(argument)
        if url:
            return url.group(1)
    return None


def gh_json(arguments, cwd):
    """The JSON a `gh` command prints. Raises if gh is missing, fails or is slow."""
    result = subprocess.run(["gh"] + arguments, cwd=cwd, capture_output=True, text=True, timeout=10, check=True)
    return json.loads(result.stdout)


def merged(target, cwd, now=None):
    """The pull requests GitHub says are merged, as URLs; None if it cannot be asked.

    With a number, that pull request if it is merged. Without one, every
    pull request merged in the last few minutes, since after a merge the
    branch it belonged to may be gone.
    """
    try:
        if target:
            pr = gh_json(["pr", "view", target, "--json", "state,url"], cwd)
            return [pr["url"]] if pr["state"] == "MERGED" else []
        now = now or datetime.now(timezone.utc)
        prs = gh_json(["pr", "list", "--state", "merged", "--limit", "10", "--json", "url,mergedAt"], cwd)
        return [pr["url"] for pr in prs if now - merged_at(pr) <= RECENT]
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        return None


def merged_at(pr):
    """When a pull request from `gh pr list` was merged."""
    return datetime.strptime(pr["mergedAt"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


def message(call, merged=merged):
    """What to tell Claude about this tool call, or None when there is nothing to say.

    `merged` is the function that asks GitHub, passed in so the tests can
    answer for it.
    """
    if call.get("agent_type") == AGENT:
        return None
    command = (call.get("tool_input") or {}).get("command") or ""
    response = call.get("tool_response")
    output = (response.get("stdout") or "") if isinstance(response, dict) else ""
    cwd = call.get("cwd") or None

    parts = []
    for verb, arguments in invocations(command):
        if "--help" in arguments or "-h" in arguments:
            continue
        if verb == "create":
            urls = sorted({url.group(0) for url in PR_URL.finditer(output)})
            if urls:
                parts.append(OPENED.format(prs=", ".join(urls), agent=AGENT))
        else:
            target = merge_target(arguments)
            found = merged(target, cwd)
            if found is None:
                named = "#" + target if target else "the pull request on this branch"
                parts.append(UNCONFIRMED.format(prs=named, agent=AGENT))
            elif found:
                parts.append(MERGED.format(prs=", ".join(found), agent=AGENT))

    parts = list(dict.fromkeys(parts))
    if not parts:
        return None
    return " ".join(parts) + (SUBAGENT if call.get("agent_id") or call.get("agent_type") else "")


def main():
    try:
        text = message(json.load(sys.stdin))
    except Exception:  # noqa: BLE001 - the hook must never fail the tool call
        return
    if text:
        json.dump({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": text}}, sys.stdout)


if __name__ == "__main__":
    main()
