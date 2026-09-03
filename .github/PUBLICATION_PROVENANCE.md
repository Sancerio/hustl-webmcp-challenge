# Publication provenance

This repository preserves its existing public history while publishing the exact
audited application tree from frozen candidate
`3a412f5843c7098047673b393e04926e17872527`.

That candidate pins Hustl source commit
`f52fd2196a5e77c6eb8083df0342ed68d46aeee4`. Candidate files are exhaustively
listed in `config/public_manifest.sha256`; publication-only GitHub metadata lives
under `.github/` and is not part of the candidate tree.

CI reconstructs the disconnected, deterministic candidate repository from the
manifest, proves the exact candidate commit, and then runs its own verifier,
tests, analysis, and release build.
