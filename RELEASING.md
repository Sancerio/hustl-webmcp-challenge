# Release process

Only a repository owner may publish or deploy this evaluator. Passing CI does
not create a repository, push a commit, change visibility, or deploy a build.

1. Freeze one reviewed private source commit.
2. Run the private Git-object exporter into a new directory outside the private
   checkout. The export must have one root commit and no private Git history.
3. From the export, run the source scan, all tests, release build, manifest
   check, Gitleaks canaries and scans, and bundled-license check. After `vercel
   build --prod`, run the private
   `scripts/webmcp_public/evaluator_artifacts.mjs write` command. Supply the
   exact private source SHA, disconnected export, `.vercel/output`, pinned
   Gitleaks binary, and an external manifest path. The command rebuilds the
   export and requires byte-for-byte equality with Vercel's static output.
4. Complete an independent audit of the frozen public root commit. Resolve and
   re-review every blocker or major finding.
5. Obtain explicit owner authorization for repository creation, first push,
   and eventual public visibility.
6. Create the destination as private. Enable security advisories and private
   vulnerability reporting when GitHub offers them. Confirm the fallback in
   `SECURITY.md`, then require `Public evaluator CI` before changing visibility.
7. Push the one-root-commit public snapshot and require `Public evaluator CI`
   on `main`. Record the uploaded
   artifact digest, runner image identifiers, and GitHub build-provenance
   attestation.
8. Change visibility only after the frozen candidate, private security channel,
   and CI pass. Deploy the attested `.vercel/output` with `vercel deploy
   --prebuilt --prod`. Run `evaluator_artifacts.mjs verify-deployment` against
   the immutable deployment URL and exact `dpl_...` identifier. Use a read-only
   Vercel inspection to bind that ID to the expected project, scope, and URL.
   An alias check may follow, but an alias cannot replace the immutable URL in
   the attestation record.

   The deployment check must compare every static file and MIME type, each
   supported document route, and the dotted-path 404 byte-for-byte. Only a
   document navigation with `Sec-Fetch-Dest: document` and `Sec-Fetch-Mode:
   navigate` may carry the cookies-only `Clear-Site-Data` header. Static assets
   and other responses must not carry it. No response may set a cookie, and all
   responses must retain the required security headers.
9. Run the complete evaluator story in a managed browser at desktop and narrow
   mobile widths. Require canonical route ownership, exact tool catalogs,
   pending-only proposal creation, visible human Apply/Dismiss, stale-handle
   rejection, post-Apply readback, and zero console warnings/errors.

If the export contains an identity, private data, production origin,
credential, unexpected file, or unreviewed Git history, stop and rebuild it
from corrected frozen source. Do not rewrite or force-push a published release
to hide the problem. Publish a corrective commit and advisory.

The first public snapshot contains one reviewed Gitleaks false positive: an
ordinary local preference key in commit `569ba63b`, not a credential.
`config/gitleaks.toml` suppresses only that commit, path, and line through an
AND-matched allowlist. Current source, builds, and every other historical
location remain scanned. A canary confirms that the same text is rejected
outside the listed historical location.
