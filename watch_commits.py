#!/usr/bin/env python3
import time
import sys
import urllib.request
import urllib.parse
import json
from datetime import datetime

REPO = "project-chip/connectedhomeip"
BRANCH = "v1.6-sve-branch"
COMMITS_URL = f"https://api.github.com/repos/{REPO}/commits/{BRANCH}"
PULLS_URL = (
    f"https://api.github.com/repos/{REPO}/pulls?"
    + urllib.parse.urlencode(
        {"state": "open", "base": BRANCH, "per_page": "100", "sort": "created", "direction": "desc"}
    )
)
INTERVAL = 5 * 60

RESET = "\033[0m"
BOLD = "\033[1m"
RED = "\033[91m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
BLUE = "\033[94m"
MAGENTA = "\033[95m"
CYAN = "\033[96m"


def gh_get(url):
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "watch-commits-script",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def now():
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def print_commit(commit, is_new):
    sha = commit["sha"]
    short_sha = sha[:7]
    author = commit["commit"]["author"]["name"]
    date = commit["commit"]["author"]["date"]
    message = commit["commit"]["message"].splitlines()[0]
    url = commit["html_url"]

    if is_new:
        banner = f"{BOLD}{GREEN}{'=' * 70}{RESET}"
        print(banner)
        print(f"{BOLD}{YELLOW}*** NEW COMMIT DETECTED at {now()} ***{RESET}")
        print(banner)
    else:
        print(f"{CYAN}[{now()}] Latest commit:{RESET}")

    print(f"  {BOLD}{MAGENTA}SHA:{RESET}     {YELLOW}{short_sha}{RESET}  ({sha})")
    print(f"  {BOLD}{MAGENTA}Author:{RESET}  {GREEN}{author}{RESET}")
    print(f"  {BOLD}{MAGENTA}Date:{RESET}    {BLUE}{date}{RESET}")
    print(f"  {BOLD}{MAGENTA}Message:{RESET} {message}")
    print(f"  {BOLD}{MAGENTA}URL:{RESET}     {CYAN}{url}{RESET}")
    print()


def print_pr(pr, is_new):
    number = pr["number"]
    title = pr["title"]
    user = pr["user"]["login"]
    created = pr["created_at"]
    head = pr["head"]["label"]
    url = pr["html_url"]

    if is_new:
        banner = f"{BOLD}{MAGENTA}{'=' * 70}{RESET}"
        print(banner)
        print(f"{BOLD}{YELLOW}*** NEW PULL REQUEST DETECTED at {now()} ***{RESET}")
        print(banner)
    else:
        print(f"  {CYAN}- open PR:{RESET}")

    print(f"  {BOLD}{MAGENTA}PR:{RESET}      {YELLOW}#{number}{RESET}  {title}")
    print(f"  {BOLD}{MAGENTA}Author:{RESET}  {GREEN}{user}{RESET}")
    print(f"  {BOLD}{MAGENTA}Created:{RESET} {BLUE}{created}{RESET}")
    print(f"  {BOLD}{MAGENTA}Head:{RESET}    {head}")
    print(f"  {BOLD}{MAGENTA}URL:{RESET}     {CYAN}{url}{RESET}")
    print()


def check_commit(state):
    commit = gh_get(COMMITS_URL)
    sha = commit["sha"]
    if state["last_sha"] is None:
        print_commit(commit, is_new=False)
    elif sha != state["last_sha"]:
        print_commit(commit, is_new=True)
    else:
        print(f"{CYAN}[{now()}]{RESET} no new commit (still {YELLOW}{sha[:7]}{RESET})")
    state["last_sha"] = sha


def check_pulls(state):
    pulls = gh_get(PULLS_URL)
    current_numbers = {pr["number"] for pr in pulls}

    if state["known_prs"] is None:
        print(f"{CYAN}[{now()}] Open PRs against {BRANCH}: {len(pulls)}{RESET}")
        for pr in pulls:
            print_pr(pr, is_new=False)
        state["known_prs"] = current_numbers
        return

    new_prs = [pr for pr in pulls if pr["number"] not in state["known_prs"]]
    if new_prs:
        for pr in new_prs:
            print_pr(pr, is_new=True)
    else:
        print(f"{CYAN}[{now()}]{RESET} no new PR ({len(pulls)} open against {BRANCH})")

    state["known_prs"] = current_numbers


def main():
    print(
        f"{BOLD}{BLUE}Watching {REPO}@{BRANCH} (commits + open PRs) "
        f"every {INTERVAL // 60} min...{RESET}\n"
    )
    state = {"last_sha": None, "known_prs": None}
    while True:
        try:
            check_commit(state)
        except Exception as e:
            print(f"{RED}[{now()}] commit check error: {e}{RESET}", file=sys.stderr)

        try:
            check_pulls(state)
        except Exception as e:
            print(f"{RED}[{now()}] PR check error: {e}{RESET}", file=sys.stderr)

        try:
            time.sleep(INTERVAL)
        except KeyboardInterrupt:
            print(f"\n{YELLOW}Stopped.{RESET}")
            break


if __name__ == "__main__":
    main()
