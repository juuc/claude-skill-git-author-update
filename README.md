# git-author-update

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skill that rewrites commit authors across all repositories in a GitHub organization — making your contributions appear on your personal GitHub contribution graph ("grass").

## Why?

If you commit to an org with a work email, those contributions don't show on your personal GitHub profile. This skill changes the `GIT_AUTHOR_EMAIL` field so GitHub counts them as your personal contributions.

> **Note:** `Co-authored-by` trailers do NOT produce green squares on the contribution graph. You must change the actual commit author email.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed
- [GitHub CLI](https://cli.github.com/) (`gh`) authenticated with push access to the target org
- The target personal email must be [verified on GitHub](https://github.com/settings/emails)
- The target account should be a [member of the org](https://docs.github.com/en/organizations/managing-membership-in-your-organization) (required for private repo contributions)

## Installation

### One-line install

```bash
git clone https://github.com/juuc/claude-skill-git-author-update.git /tmp/claude-skill-git-author-update \
  && bash /tmp/claude-skill-git-author-update/install.sh \
  && rm -rf /tmp/claude-skill-git-author-update
```

### Manual install

```bash
# Clone the repo
git clone https://github.com/juuc/claude-skill-git-author-update.git
cd claude-skill-git-author-update

# Run installer
bash install.sh
```

This copies two files to `~/.claude/commands/`:
- `git-author-update.md` — The Claude Code skill prompt
- `git-author-update.sh` — The batch update script

### Verify installation

```bash
ls ~/.claude/commands/git-author-update.*
```

## Usage

### Via Claude Code (recommended)

Open Claude Code and type:

```
/user:git-author-update
```

Claude will walk you through the entire process:
1. Ask for your org name, emails, and date range
2. Verify prerequisites (gh auth, org membership)
3. Run the batch update in the background
4. Monitor progress and report results
5. Verify contribution count via GitHub API

### Via CLI directly

```bash
bash ~/.claude/commands/git-author-update.sh \
  --org "your-org" \
  --old-email "work@company.com" \
  --new-name "your-github-username" \
  --new-email "personal@gmail.com" \
  --since "2025-01-01" \
  --until "2026-01-01"
```

#### Options

| Flag | Required | Description |
|------|----------|-------------|
| `--org` | Yes | GitHub organization name |
| `--old-email` | Yes | Current commit author email to replace |
| `--new-name` | Yes | New author name (GitHub username) |
| `--new-email` | Yes | New author email (must be verified on GitHub) |
| `--since` | Yes | Start date (`YYYY-MM-DD`, inclusive) |
| `--until` | Yes | End date (`YYYY-MM-DD`, exclusive) |
| `--skip` | No | Comma-separated repo names to skip |
| `--dry-run` | No | Rewrite locally but don't push |

#### Monitor progress

```bash
tail -f /tmp/git-author-update-*/batch.log
```

#### Example output

```
[01:06:07] === Git Author Batch Update ===
[01:06:07] Org: myorg
[01:06:07] From: work@company.com -> To: username <personal@gmail.com>
[01:06:07] Date range: 2025-01-01 to 2026-01-01
[01:06:09] Found 65 repositories
[01:06:09] [1/65] repo-a — cloning...
[01:06:11] [1/65] repo-a — rewriting 42 commits...
[01:07:47] [1/65] repo-a — DONE (42 commits)
...
[01:53:14] DONE: 27 repos (7577 commits) | SKIP: 38 | FAIL: 0
```

## How it works

1. Lists all repos in the org via `gh repo list`
2. Clones each repo, counts commits matching the old email + date range
3. Runs `git filter-branch --env-filter` to change `GIT_AUTHOR_NAME` and `GIT_AUTHOR_EMAIL`
4. Also cleans up any existing `Co-authored-by` trailers via `--msg-filter`
5. Force-pushes all branches and tags
6. Cleans up cloned repos after successful push

## Important notes

- **Irreversible.** This rewrites git history and force-pushes. Use `--dry-run` first to test.
- **Large repos are slow.** `filter-branch` processes every commit in a repo, not just matching ones. A repo with 10k commits may take 10-20 minutes.
- **GitHub reindex takes ~30 minutes.** After the push, the contribution graph updates within about 30 minutes.
- **Branch protection** may block force-push on some repos. These are logged as FAILED.
- **macOS + Linux compatible.** Uses `grep -oE` (not `-oP`), handles both `date -r` (macOS) and `date -d` (Linux).

## Uninstall

```bash
bash uninstall.sh
# or manually:
rm ~/.claude/commands/git-author-update.md ~/.claude/commands/git-author-update.sh
```

## License

MIT
