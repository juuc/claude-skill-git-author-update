# git-author-update

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skill that rewrites commit authors across all repositories in a GitHub organization — making your contributions appear on your personal GitHub contribution graph ("grass").

## Why?

If you commit to an org with a work email, those contributions don't show on your personal GitHub profile. This skill changes the `GIT_AUTHOR_EMAIL` field so GitHub counts them as your personal contributions.

> **Note:** `Co-authored-by` trailers do NOT produce green squares on the contribution graph. You must change the actual commit author email.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed
- [GitHub CLI](https://cli.github.com/) (`gh`) authenticated with push access to the target org
- The target personal email must be verified on GitHub (Settings > Emails)
- The target account should be a member of the org (required for private repo contributions)

## Installation

### One-line install

```bash
git clone https://github.com/juuc/claude-skill-git-author-update.git /tmp/claude-skill-git-author-update \
  && bash /tmp/claude-skill-git-author-update/install.sh \
  && rm -rf /tmp/claude-skill-git-author-update
```

### Manual install

```bash
git clone https://github.com/juuc/claude-skill-git-author-update.git
cd claude-skill-git-author-update
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

Claude handles the entire process through 7 steps, confirming with you at every decision point:

#### Step 1: Detect environment
- Runs `gh auth status` to find logged-in accounts
- Reads `~/.ssh/config` to detect SSH host aliases
- Tests SSH connectivity with `ssh -T`
- **Asks you to confirm:** active account, SSH host alias, GitHub hostname

#### Step 2: Gather parameters
- **Asks you for:** org name, old email, new username, new email, date range
- **Asks you for (optional):** repos to skip, dry-run mode

#### Step 3: Verify prerequisites
- Checks org membership via API
  - If not a member → **asks you:** "Should I send an invitation?"
  - If yes → **asks you:** "I need to switch accounts to accept. Proceed?"
  - Handles the full invite-and-accept flow automatically
- **Asks you to confirm:** "Is your email verified on GitHub?" (blocks until yes)

#### Step 4: Pre-flight checks (read-only, nothing modified)
- **4a. Scan all repos** — clones each, counts matching commits, shows full table
  - **Asks you:** "Does this look correct? Any repos to skip?"
  - Stops if 0 commits found
- **4b. Test clone + push** — tests access on the smallest affected repo
  - Stops if credentials or permissions fail
- **4c. Dry-run rewrite** — runs the script with `--dry-run` on one repo
  - Stops if filter-branch fails (catches macOS compat issues, date parsing, etc.)
- **4d. Record baseline** — gets current contribution count for before/after comparison

#### Step 5: Final confirmation
- Shows full parameter summary table
- Shows all pre-flight check results
- Shows affected repos count + commit count
- **"This is irreversible. Proceed?"** (blocks until explicit yes)

#### Step 6: Execute + monitor
- Runs script in background
- Monitors log file periodically until completion

#### Step 7: Verify results
- Queries contribution count via GitHub GraphQL API
- Compares with baseline from Step 4d
- Reports: repos updated, commits rewritten, contribution count change

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
| `--ssh-host` | No | SSH host alias from `~/.ssh/config` (e.g., `github.com-work`) |
| `--git-host` | No | GitHub hostname (default: `github.com`, for GHE: `github.mycompany.com`) |
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
[01:06:07] Protocol: SSH (host: github.com-work)
[01:06:09] Found 65 repositories
[01:06:09] [1/65] repo-a — cloning...
[01:06:11] [1/65] repo-a — rewriting 42 commits...
[01:07:47] [1/65] repo-a — DONE (42 commits)
...
[01:53:14] DONE: 27 repos (7577 commits) | SKIP: 38 | FAIL: 0
```

## How it works

1. Lists all repos in the org via `gh repo list`
2. Clones each repo (via SSH or HTTPS), counts commits matching the old email + date range
3. Runs `git filter-branch --env-filter` to change `GIT_AUTHOR_NAME` and `GIT_AUTHOR_EMAIL`
4. Cleans up any existing `Co-authored-by` trailers via `--msg-filter`
5. Force-pushes all branches and tags
6. Cleans up cloned repos after successful push

## Manual steps (browser only)

The entire flow is automated by Claude Code **except:**

1. **`gh auth login`** — when a GitHub account is not yet on the CLI, browser OAuth is required
2. **Email verification** — you must confirm your email is verified at GitHub Settings > Emails

Everything else — account switching, org invitations, invitation acceptance, pre-flight checks, script execution, monitoring, and verification — is fully automated.

## Important notes

- **Irreversible.** This rewrites git history and force-pushes. The skill runs pre-flight checks and a dry-run test before touching anything.
- **Large repos are slow.** `filter-branch` processes every commit in a repo, not just matching ones. A repo with 10k commits may take 10-20 minutes.
- **GitHub reindex takes ~30 minutes.** After the push, the contribution graph updates within about 30 minutes.
- **Branch protection** may block force-push on some repos. These are logged as FAILED and caught in pre-flight.
- **macOS + Linux compatible.** Uses `grep -oE` (not `-oP`), handles both `date -r` (macOS) and `date -d` (Linux).
- **GitHub Enterprise supported.** Use `--git-host` for custom hostnames.

## Uninstall

```bash
bash uninstall.sh
# or manually:
rm ~/.claude/commands/git-author-update.md ~/.claude/commands/git-author-update.sh
```

## License

MIT
