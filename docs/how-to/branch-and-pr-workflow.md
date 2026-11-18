# Branch and pull request workflow

How every change reaches `main` in this repo. The rules are in `CLAUDE.md` → Workflow; this is
the how. Run everything from the repo root.

Two words used throughout:

- **`origin`** is the nickname for the GitHub copy of the repo (`git remote -v` shows the URL).
- **`origin/main`** is your Mac's *bookmark* of where GitHub's `main` was at the last
  `git fetch`. It only moves when you fetch or pull, so fetch before trusting it.

## The normal case

```bash
# 1. Start from an up-to-date main
git switch main
git pull --ff-only

# 2. Branch: <prefix>/<a-few-words>
git switch -c fix/dark-launch-colour

# 3. Work, then commit one concern at a time
git add -p                      # pick the chunks that belong to this commit
git diff --staged               # last look at exactly what will be committed
git commit -m "fix: launch in dark mode uses the dark text colour" -m "Why, in a sentence or two."

# 4. Push (first time with -u, then plain git push)
git push -u origin fix/dark-launch-colour

# 5. Open the PR (the template fills in the sections)
gh pr create --base main
gh pr view --web                # read your own diff in Files changed before merging

# 6. Merge: squash, from the PR
gh pr merge --squash

# 7. Clean up
git switch main
git pull --ff-only
git branch -d fix/dark-launch-colour        # see "Deleting after a squash" if it refuses
git push origin --delete fix/dark-launch-colour
git fetch --prune
```

Why each step matters:

1. **Pull first.** A branch starts from whatever `main` you have locally. A stale one means
   building on old code and conflicts you didn't need. A PR merges on GitHub, so your Mac is
   always one merge behind until you pull.
2. **Branch per change.** `main` only ever receives reviewed, finished work, so it always
   builds and you can always branch from it.
3. **One concern per commit.** Each commit can be read, and if needed undone, on its own.
   Squash flattens them on `main`, but while the PR is open they are how you review and
   back out steps.
4. **Push early.** A commit only on your laptop is not backed up. `-u` links the branch to
   GitHub's copy so `git status` can say "ahead 2" (unpushed work).
5. **PR description.** What, why, how verified. The squash commit on `main` links to the PR
   (`(#N)` in its subject), so this is the long-form "why" for that commit forever.
6. **Squash.** One PR becomes one commit on `main`: a readable history where every entry is
   a whole, reviewed change you can revert in one go.
7. **Clean up.** Dead branches pile up until nobody can tell what's in flight.

### Names and messages

| Prefix | Use for |
|---|---|
| `feat` | something new the user can do |
| `fix` | a bug |
| `docs` | documentation only |
| `refactor` | restructure, no behaviour change |
| `chore` | tooling, config, housekeeping |
| `test` | tests only (commit prefix) |

Branch: `fix/dark-launch-colour`. Commit and PR title: `fix: launch in dark mode uses the dark
text colour`. The subject says what changes in effect, under ~72 characters; the body says why,
because the diff already says what. The PR title becomes the squash commit's subject.

## When things go sideways

### Branch is behind main

`main` moved while you worked (another PR merged). Bring it into your branch:

```bash
git fetch
git merge origin/main           # on your branch
# resolve conflicts if any (next section), run the tests, then
git push
```

Do this before merging if `main` changed anything near your work: your tests ran against the
old `main`, and the combination is what will ship. Merging `main` in adds a merge commit to the
branch, which squash discards, and needs no force push.

The alternative teams use is `git rebase origin/main`, which replays your commits on top of the
new `main` for a straight history. It rewrites your commits, so the push must be
`git push --force-with-lease`. Only do that on a branch nobody else has checked out.
`--force-with-lease` refuses if GitHub has commits you haven't seen, where plain `--force` would
silently erase them.

### Merge conflict

Two branches changed the same lines, and git won't guess which wins. It stops, and the file
contains both versions:

```
<<<<<<< HEAD
your branch's version
=======
main's version
>>>>>>> origin/main
```

```bash
git status                      # lists the conflicted files ("both modified")
# edit each file: keep the right combination, delete all three marker lines
git add <file>
git commit                      # after a merge
# (after a rebase, git rebase --continue instead)
```

Then build and test. A conflict-free result can still be wrong if the two changes interact.
Lost or confused: `git merge --abort` (or `git rebase --abort`) puts everything back as it was
before you started.

### Committed on the wrong branch

Not committed yet: just create the branch. Uncommitted changes come with you.

```bash
git switch -c fix/the-right-name
```

Committed on `main` by mistake (not pushed):

```bash
git branch fix/the-right-name         # label the commit so it's kept
git reset --hard origin/main          # move main back to GitHub's main
git switch fix/the-right-name
```

`reset --hard` throws away uncommitted changes, so commit or stash them first. Check that
`git log fix/the-right-name` shows your commit before resetting. If you pushed to `main`,
don't rewrite it; undo with a revert PR (below).

### Undo a commit

| Situation | Command | Effect |
|---|---|---|
| Last commit, not pushed | `git reset --soft HEAD~1` | Removes the commit, keeps its changes staged |
| Fix the last commit's message or add a forgotten file, not pushed | `git commit --amend` | Replaces the last commit |
| Already pushed to your branch | `git revert <hash>` | New commit that undoes it; history kept |
| Already merged to `main` | Revert button on the merged PR | Opens a PR that undoes it |

Rule: rewriting history (`reset`, `amend`, `rebase`) is fine for commits only you have.
Once pushed, prefer `revert`, which adds instead of rewriting.

### PR needs changes

Don't open a new PR. Fix it on the same branch:

```bash
git add <files>
git commit -m "docs: <what the feedback was about>"
git push                        # the PR updates itself
```

Reply to each comment ("Fixed in 7501c8c", or why you kept it), then **Resolve conversation**.
Add new commits rather than amending: a reviewer sees just what changed since their last
look, and squash tidies it all on merge anyway.

### Deleting a branch after a squash

The squash commit on `main` is new, so git can't see your branch's commits in it.
`git branch -d` may refuse ("not fully merged"), or delete with a warning if GitHub's copy of
the branch still exists. Before forcing it with `-D`, check you'd lose nothing:

```bash
# right after merging, before main moves on: no output means identical
git diff --stat main fix/dark-launch-colour

# any time later: state should be MERGED and both hashes equal
gh pr view fix/dark-launch-colour --json state,headRefOid --jq '.state + " " + .headRefOid'
git rev-parse fix/dark-launch-colour
```

Never keep working on a branch after its PR merged: start a new one from `main`.

## Solo: what pays off and what's ceremony

Pays off alone: pulling before branching, one concern per PR, commit messages that say why,
pushing as backup, the PR description and its checklist, reading your own diff on the PR page,
squash, cleanup.

Ceremony alone: requesting reviewers, approvals and verdicts (GitHub won't let you approve your
own PR), draft PRs. Don't require approvals on `main`, or you can't merge. A ruleset that only
requires a pull request (0 approvals) is real protection against pushing to `main` by accident.

## Reading the output

- `git status -sb` → `## fix/x...origin/fix/x [ahead 1]`: one commit not pushed yet.
  `[behind 1]`: GitHub has a commit you haven't pulled.
- `git branch -av` → green `*` is the branch you're on; red `remotes/origin/...` lines are
  bookmarks of GitHub, not branches you work on.
- `~` lines and `(END)`: you're in the pager. Press `q`.
