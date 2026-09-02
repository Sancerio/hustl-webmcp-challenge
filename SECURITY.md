# Security policy

## Supported version

Security fixes are made on the latest `main` branch. The evaluator uses only
synthetic data and is separate from the production Hustl application.

## Reporting a vulnerability

Use the repository's private GitHub security-advisory reporting flow.
If GitHub does not show that flow, open a content-free issue titled "Security
contact requested" without reproduction details, private values, or affected
paths; a maintainer will provide a private channel. Never disclose a suspected
credential, privacy, browser-state, WebMCP authorization, or supply-chain
vulnerability in a public issue.

Include the affected commit, route/tool, reproduction, impact, and whether the
issue can expose inherited browser state, escape same-origin isolation, bypass
human proposal review, or make a stale tool act on a new page.

## Security invariants

- no real account, health, nutrition, workout, or identity data;
- no production endpoint, authentication, telemetry, or persistent storage;
- no cross-origin or credentialed network transport;
- no WebMCP decision tool or automatic proposal application;
- exact reviewed-source manifest and independent public Git history;
- browser-state clearing/blocking before Flutter bootstrap;
- cookie-clearing response headers scoped to evaluator documents and deep
  links, with credentialless static build assets excluded;
- route and state generation checks that fail stale handles closed;
- commit-pinned external Actions, exact language/scanner versions, verified SDK
  and scanner checksums, no local composite Actions, release artifact hashes,
  and main-branch provenance;
- recorded GitHub-hosted runner image identifiers (the vendor-managed base
  image is updated over time and is not represented as byte-reproducible).
