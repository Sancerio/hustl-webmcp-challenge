# Security policy

This repository intentionally contains no production credentials or live
service configuration. Please do not add any.

Report a suspected secret, unsafe network escape, private-data fixture, or
silent mutation path privately to the repository owner. Include the affected
file, reproduction steps, and whether a built artifact is involved. Do not
publish a real token or user record in an issue.

The supported evaluator is the exact pinned source and dependency lockfile in
the current repository. Its browser runtime is expected to work offline. Any
unexpected non-local request, credential API access, or mutation reported as
applied without an explicit review action is a security bug.
