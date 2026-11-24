# Deployment repository

Keep this repository almost entirely Nix. Use Nix modules and simple just
recipes for deployment. Do not add Python deployment tooling or a separate
test harness. Validate with Nix evaluation/builds and command previews.
Prefer explicit per-host commands. Use just's built-in dry runs, confirmations
and recipe dependencies instead of custom dispatch or command-building logic.

Keep host-owned application code alongside its host configuration in this
monorepo. Upstream packages may still be consumed as pinned dependencies.
Ask before generalizing differing host settings; use ordinary NixOS module
overrides for intentional exceptions.

`deploy` means destructive first installation. `switch` updates an existing
host. Do not run either against live machines unless the user requests it.

## Workflow

Changes here and in `~/src/nix` follow this order:

1. Work on a branch in a worktree under `../worktrees/`, never under `/tmp`.
2. Rebase that branch on `master` and fast-forward `master` to it. Do not land
   copies of its commits, which leave the branch looking unmerged.
3. Push `master` to GitHub.
4. For changes in `~/src/nix`, update the pin here, commit it to `master` and push.
5. Run `switch` from `master` and verify the host.
6. Remove the worktree with `git worktree remove` and the branch with
   `git branch -d`. Do not force either; a refusal means work has not landed.

Steps 2 to 5 need the user's request. A request to deploy covers all of them,
and step 6 follows without asking. Changes with nothing to deploy skip step 5.

Work is finished only after step 6. If it stops earlier, end by naming the branch,
its unmerged commits and the next step. Before ending a task, check
`git branch --no-merged master` in both repositories and report any of its
branches left there.

`master` must always contain every deployed commit, and the main checkouts must
match it, so fast-forward them in the same step. Commits pinned through a flake
input must be on that repository's `master` too. Always push `master` to GitHub
after committing to it, in both repositories.
