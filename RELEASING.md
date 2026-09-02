# Release process

Publishing is an explicit owner action. Passing CI does not create a public
repository, push code, or deploy the evaluator.

1. Freeze one reviewed private source commit.
2. Run the private Git-object exporter into a new directory outside the private
   checkout. The result must have one root commit and no private Git history.
3. Run source scanning, all tests, a release build, exact-manifest verification,
   checksum-pinned Gitleaks canaries plus source/full-history/build scans, and
   shipped-license verification from the exported repository. After
   `vercel build --prod`, run the private
   `scripts/webmcp_public/evaluator_artifacts.mjs write` command with the exact
   private source SHA, disconnected export, `.vercel/output`, pinned Gitleaks
   binary, and an external manifest path. It independently rebuilds the export
   and requires byte-for-byte equality with the Vercel static output.
4. Complete an independent audit of the frozen public root commit. Resolve and
   re-review every blocker or major finding.
5. Obtain explicit owner authorization for repository creation, first push,
   and eventual public visibility.
6. Create the destination as private first. Enable security advisories and
   private vulnerability reporting when GitHub offers it; verify the safe
   fallback in `SECURITY.md`; configure `Public evaluator CI` as a required
   check before changing visibility.
7. Push the one-root-commit public snapshot and require `Public evaluator CI`
   on `main`. Record the uploaded
   artifact digest, runner image identifiers, and GitHub build-provenance
   attestation.
8. Change visibility only after the frozen candidate, security channel, and CI
   all pass. Deploy only the attested `.vercel/output` with `vercel deploy
   --prebuilt --prod`, then run `evaluator_artifacts.mjs verify-deployment`
   against the immutable deployment URL and exact `dpl_...` identifier. A
   read-only Vercel inspection must bind that ID to the pinned evaluator
   project, scope, and probed URL; mutable aliases are forbidden. It verifies
   every static file with its exact MIME type, all
   supported document routes, and the dotted 404 byte-for-byte. Only document
   navigations with both `Sec-Fetch-Dest: document` and `Sec-Fetch-Mode:
   navigate` may carry cookies-only `Clear-Site-Data`; static assets and other
   responses must not. All responses must retain the exact common security
   headers and must not set cookies.
9. Run the complete evaluator story in a managed browser at desktop and narrow
   mobile widths. Require canonical route ownership, exact tool catalogs,
   pending-only proposal creation, visible human Apply/Dismiss, stale-handle
   rejection, post-Apply readback, and zero console warnings/errors.

If any identity, private data, production origin, credential, unexpected file,
or unreviewed Git history appears, stop and rebuild the public root commit from
the corrected frozen source. Do not rewrite or force-push a published release
to conceal the problem; publish a clear corrective commit and advisory.
