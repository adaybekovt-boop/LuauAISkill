# Track: debugging

Use for: "doesn't work", errors, desync, flaky behaviour, "works in Studio but not live".
Load: [debugging playbook](../references/debugging-playbook.md) → the track of the failing system.

Method: reproduce (Server & Clients for anything networked) → read both Output views → form one hypothesis →
check it with the smallest probe → fix → re-test the same scenario → report what was verified and what wasn't.
Never "fix" by wrapping in pcall, adding `task.wait()` delays or deleting checks.
Evals: `evals/cases/debugging.jsonl`.
