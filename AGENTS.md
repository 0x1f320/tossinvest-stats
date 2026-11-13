# Agent guidelines

Rules for anyone, human or agent, working in this repository. `CLAUDE.md` imports this file, so Claude Code and Codex follow the same rules. Where these rules differ from personal or global instructions, these win for this repository.

## Language

- **English:** write everything in the repository in English: code comments, `README.md`, these guideline files, commit messages, PR titles and PR bodies.
- **Korean UI:** user-facing app text stays in Korean, since the app is built for Toss Securities users. This covers menus, settings, popovers, alerts and error messages shown in the UI.

## Commits

- **Conventional Commits:** use `type(scope): summary`.
  - Common types: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `ci`, `chore`.
  - Scopes in use: `api`, `stock`, `asset`. Omit the scope when a change spans areas.
- **Summary:** imperative and lowercase, with no trailing period.
- **Body:** explains what changed and why.
- **First commit:** the history starts with `chore: initial commit` on `main`. Leave it as is.

### Author identity

Every commit must be authored by **0x1f320**, never by another account such as `async3619`. Set the identity locally in this clone, not globally:

```bash
git config user.name "0x1f320"
git config user.email "272846942+0x1f320@users.noreply.github.com"
```

Push, open PRs and merge as 0x1f320, with a token from that account. Squash and merge commits made on GitHub use the account's default commit email; that is expected.

## Branches

- **`dev`** is the default branch.
  - All work lands here through pull requests.
  - The `dev` ruleset requires a PR and allows only **squash merge**.
- **`main`** receives `dev` only through a pull request from `dev`.
  - The `main` ruleset requires a PR and allows only **create a merge commit**.
  - Before the first such PR, `main` holds only `chore: initial commit`.
- **Both branches** are protected from deletion and force pushes. No account bypasses the rulesets, so never push to `dev` or `main` directly.
- **Feature branches** are named `<type>/<short-topic>`, for example `feat/asset-popover` or `ci/scaffold`.
- **Detached worktrees:** when a worktree starts on a detached commit, create a branch named `worktree-<unix timestamp>` right away.

## Pull requests

- **One PR per logical step:** build features as a series of small, reviewable PRs, each of which builds and passes tests on its own.
- **Draft:** open PRs as Draft.
- **Title:** the conventional commit summary of the change, for example `feat(asset): show holdings breakdown popover`. The squash commit on `dev` takes the PR title and appends `(#N)`.
- **Body:** use these sections:
  - **Summary:** what the change does, from the user's point of view.
  - **Changes:** the files and types touched.
  - **Why:** the decisions and their reasons.
  - **Testing:** what was actually run.
- **Honest testing:** never claim a check that didn't happen. If something could not be verified (for example, live API data while the IP is not registered), say so.
- **Squash message:** the squash commit message is the PR body. End it with any `Co-Authored-By` trailer that applies.
- **No Linear:** this repository does not use Linear. Don't create issues for it and don't prefix titles with `[WEB-XXXXX]`.
- **No private details:** never put local paths, other project names or private details in commits, PRs or docs. The repository is public.

### Stacked PRs

When a feature is split into stacked PRs, each PR is based on the branch of the one before it, and they merge in order.

Because `dev` only allows squash merges, the next branch still contains the parent's original commits after the parent merges. Restack it before merging it:

```bash
git fetch origin
git rebase --onto origin/dev <old tip of the parent branch> <branch>
git push --force-with-lease origin <branch>
```

- **Check the restack:** the rebased tip's tree (`git rev-parse HEAD^{tree}`) must equal the tree that passed CI.
- **Base branch:** GitHub retargets the PR to `dev` when the parent's branch is deleted on merge. If it didn't, change the base to `dev`.

## Build, test, CI

| Command | Purpose |
| --- | --- |
| `swift build` | Debug build |
| `scripts/test.sh` | Swift Testing suite; works with only the Command Line Tools installed |
| `scripts/build-app.sh [release\|debug]` | Builds and ad-hoc signs `build/TossBar.app` |
| `TOSSBAR_DIAG=1 build/TossBar.app/Contents/MacOS/TossBar` | Prints each menu bar item's state and API errors every 3 s |

- **CI:** `.github/workflows/ci.yml` runs on every PR and on pushes to `dev` and `main`. It builds, runs the tests, builds the release bundle, and uploads it as an artifact.
- **Before opening a PR:** run `swift build` and `scripts/test.sh` locally.
- **Tests:** add them for logic that can be tested without the UI or network: decoding, formatting, conversion and profit math, and backward-compatible config decoding.

## Design invariants

Keep these unless a change deliberately revisits them and the PR explains why.

- **Every number comes from the Toss Securities OpenAPI.**
  - Profit and rates, including after-fee/tax figures, are the API's values.
  - The only local math is converting USD to KRW at the base rate (`midRate`, 매매기준율).
- **One item, one status item.** Each configured item is its own `NSStatusItem`:
  - Its stable `autosaveName` is `TossBar.<uuid>`.
  - Edits update it in place; it is never recreated.
  - Deleting an item forgets only that item's saved position.
  - This keeps positions stable with macOS and menu bar managers (Thaw, Ice).
- **Status item behavior:**
  - `behavior = []` (menu bar managers simulate ⌘-drag).
  - Fixed width that only grows, padded by text width + 4 pt.
  - The title is reassigned only when it changes.
- **Menu bar text is always white.**
- **Asset title format:** `{profit}₩ ({rate}%)`, for example `+1,019,000₩ (+11.79%)`.
- **Secrets live in user-only files,** not the Keychain: `~/Library/Application Support/TossBar/`, with a `0700` directory and `0600` files.
  - **Why:** the Keychain re-prompts after every ad-hoc re-sign.
- **Respect the API's limits:**
  - Only one token per client is valid, so cache it.
  - Space requests per rate limit group.
  - Batch price requests across all items.
- **Saved configs stay backward compatible.** New fields use `decodeIfPresent` with defaults, so existing `menuItems.v1` data keeps loading.
- **Bundle id `dev.tossbar.TossBar` stays fixed.** Changing it resets user settings and the macOS "Allow in Menu Bar" entry.
