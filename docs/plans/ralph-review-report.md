# Ralph Review report and Run archive

Status: implemented and deployed to Nero on 2026-11-09 through shared revision
`0813b04` and deployment pin `69c9fbf`. Production feedback tightened the human
renderer to approved structured fields and a brief coverage notice; raw coverage
logs remain in the archive. See the service operations guide for the final
refresh procedure. The design below records the original plan.

## Outcome

Give readers a Review report containing the approved review and enough evidence
to assess its findings. Keep the Run archive at `/traces` for investigating the
analysis. Add `/report` for the human-facing page. Defer human challenges and
corrections to a separate change.

The judge continues to write approved wording once. There is no additional
summarizer, editorial model call, or second version of a finding to reconcile.
Both pages use the same persisted result. This change should add no inference
cost and should not change which findings qualify for publication.

## What exists today

The engine already separates approved text from diagnostics:

- `pkgs/ralph/agents/judge/prompt.md` controls final approved wording.
- `pkgs/ralph/final_comment/` renders comments and the detailed review.
- `pkgs/ralph/ralph/pipeline.py` stores that rendered review as result content.
- `pkgs/ralph-service/ralph_service/report.py` saves a public JSON snapshot and
  renders a page containing the review, concept assessment, coverage, finding
  attribution, challenger outcomes, final decisions, agent outputs and usage.

That last page is currently called the Review Report. It repeats findings across
several diagnostic sections, even though the approved review already exists.
Separating those sections is the first improvement; a pipeline rewrite is
unnecessary.

These package paths are in `/home/will/src/nix`. Host routing belongs in
`/home/will/deployments/hosts/nero/configuration.nix`.

## Page contents

The Review report contains:

- PR link, reviewed revision, completion time and review status.
- All current verified findings, ordered by severity, with source locations,
  approved explanations, material qualifications and suggested corrections.
- Approved concept objections or backport conclusions when applicable.
- Specific coverage limitations that affect how the review can be used.
- A short notice for unresolved previous concerns, linked to archive history.
- Links to the matching Run archive and previous runs.

Retain the concise comment's six-finding limit, but make every current verified
finding discoverable in the report. Do not repeat a finding in a second report
section. Reuse the existing summary and expandable explanation presentation
initially; the explanation should add evidence rather than restate the summary.
No overall ACK/NACK or merge-readiness verdict is introduced.

The Run archive retains the existing diagnostic sections, historical findings
and replies, alternatives, model/stage metadata, usage and public JSON download.
Label intermediate and rejected claims as such. Link to the matching Review
report instead of embedding another copy of the whole approved review.
Diagnostic records can still contain the original text they are recording.

Preserve public-record filtering and private trace storage. The archive remains
the existing public diagnostic projection, not an HTTP view of private state.

## URLs and storage

Keep current run IDs and repository namespaces:

| View | Core | Other repositories |
| --- | --- | --- |
| Review report | `/report/<id>.html` | `/report/<repo>/<id>.html` |
| Run archive | `/traces/<id>.html` | `/traces/<repo>/<id>.html` |
| Public run record | `/traces/<id>.json` | `/traces/<repo>/<id>.json` |

Keep the existing archive files and canonical JSON in `reportDir`. Put human
HTML under `reportDir/reports`, with matching repository subdirectories. Serve
that directory through a new static Caddy `/report/*` route. Reuse theme assets,
HTML sanitization and security headers. No application HTTP server is needed.

Use `reportBaseUrl` for `/report` and an explicit `archiveBaseUrl` for `/traces`.
Thread the distinction through existing configuration rather than deriving one
URL by replacing text in the other. Do not duplicate the JSON record or add a
second run to the history/stats indexes.

Keep run history under `/traces/`, adding Review report and Run archive links
per entry. The report's previous-runs link goes there. `/report/` can link or
redirect to this existing index; a second history browser is unnecessary.

## Implementation sequence

1. **Split static rendering and persistence.** Extract the human page from the
   existing report renderer and retain the diagnostic renderer as the archive.
   Generate both from the saved public snapshot. Extend `save_report` recovery
   so a retry writes a missing page from that snapshot, even when the other HTML
   already exists. Publish links only after the required artifacts exist.
   Preserve immutable run identity and avoid rerunning inference on retries.

2. **Trim the approved review presentation.** Adjust the existing report
   templates/renderer to put detailed history and diagnostic alternatives in
   the archive. Keep actionable approved objections and essential evidence in
   the report. Tighten the existing judge prompt to avoid repeating a claim
   across title, summary and explanation. Prefer one short explanation per
   finding, allowing extra detail when needed to substantiate it. Do not impose
   a word limit that drops qualifications. Keep template snapshots in run
   identity and replay, as they are today.

3. **Wire URLs and navigation.** Add the archive URL configuration and static
   route. Point new GitHub/Forgejo comments, notifications and ordinary stats
   links at `/report`. Keep diagnostic links such as `#challenger` on `/traces`.
   Update history links, theme asset paths and report availability checks.
   Replace user-facing “full report” wording with the appropriate page name.

4. **Prepare historical pages and cut over.** Extend the existing `backfill.py`
   offline/dry-run workflow over public JSON records. Generate human pages and refresh archive
   navigation without paid calls, GitHub writes or changes to saved claims.
   Older approved prose may remain verbose; do not rewrite it with a model.
   Verify representative stored formats before enabling new links. If a record
   cannot support a human report, keep its archive accessible and show report
   unavailable rather than inventing a review. All new runs use the split;
   there is no legacy rendering switch. Old `/traces` links remain archives.

Use small atomic commits for these changes and release them together. Pin and
switch Nero only when deployment is requested.

## Verification and acceptance

Start with existing preview fixtures and a few saved public run records:
a normal review, more than six findings, no findings, incomplete/failed
verification, retained historical concerns, a backport and a non-Core run.

Extend the existing package tests to check that both pages reference the same
run and approved findings; dropped or unverified candidates cannot enter the
report; missing-page recovery uses persisted content; and history/stats count
each run once. Verify incomplete coverage remains visible and “no findings”
cannot imply successful verification when it failed. Test links to both pages,
including diagnostic anchors and repository namespaces.

Read before/after HTML previews. A reader should find what needs attention
within a minute and assess one finding without reading the archive. Check that
removing repeated sections has not removed the evidence or qualifications that
make the finding assessable. Keep prompt-quality assessment separate from
deterministic renderer tests; do not assert arbitrary prose lengths.

Run relevant existing engine/service tests, build `ralph` and `ralph-service`,
and evaluate Nero's Nix configuration and Caddy routes. No live deployment,
external publication or paid review is needed to validate this implementation.
