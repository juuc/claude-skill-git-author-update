# Git Author Batch Update

Rewrite commit authors across all repositories in a GitHub organization. Changes `GIT_AUTHOR_EMAIL` and `GIT_AUTHOR_NAME` so commits appear on the target GitHub contribution graph ("grass").

## What this skill does

1. Clones all repositories from a GitHub org
2. Rewrites commit author for commits matching the old email within a date range
3. Force-pushes the rewritten history
4. Verifies contribution count via GitHub API

## Instructions

When the user invokes this skill, follow these steps:

### Step 1: Detect auth and SSH context

Before asking anything, run these commands to detect the user's environment:

```bash
# 1. Check gh CLI auth state
gh auth status

# 2. Check git protocol preference
gh config get git_protocol 2>/dev/null

# 3. Check SSH config for GitHub host aliases
grep -E "^Host " ~/.ssh/config 2>/dev/null | grep -i git
```

Parse the output to identify:
- Which gh account(s) are logged in
- Which account is currently active and its token scopes
- Git protocol preference (`ssh` or `https`)
- SSH host aliases for GitHub (e.g., `github.com`, `github.com-work`, `github-personal`)

Save the active account name as `WORK_ACCOUNT` for later use.

**Determine the remote protocol:**

Read the user's SSH config directly:
```bash
cat ~/.ssh/config 2>/dev/null
```

Parse the file to find Host entries that connect to `github.com` (look for `HostName github.com`). Each entry maps a Host alias to an SSH key (IdentityFile). For example:
```
Host github.com-work
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_work

Host github.com-personal
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_personal
```

For each GitHub Host entry found, test which one authenticates as the **work account** (the one with push access to the org):
```bash
ssh -T git@HOST_ALIAS 2>&1
# Output: "Hi WORK_ACCOUNT! You've successfully authenticated..."
```

Auto-select the SSH host alias that authenticates as the work account. Save it as `SSH_HOST` — this will be passed as `--ssh-host` to the script.

**If no SSH config exists** (or no GitHub entries found), ask the user which connection method to use:
- **HTTPS** (default) — uses `gh` CLI credential helper, no extra setup needed
- **SSH** — user must provide their SSH host alias or set up `~/.ssh/config` first

Save the final decision as `SSH_HOST` (the alias string, or empty for HTTPS).

**Confirm gh auth:**
- Is the **active gh account** the one with push access to the org? (It should be the work/org account.)
- If multiple accounts exist, ask which one should be used.
- If no account is logged in, guide them: `gh auth login -h GIT_HOST -s repo --web` (manual browser step). Use `github.com` as the default GIT_HOST, or the user's GitHub Enterprise hostname if applicable.
- If the active account lacks required scopes (`repo`), re-auth: `gh auth login -h GIT_HOST -s repo --web`

**Important:** The active `gh` account must have push access to the org repos. SSH is used for git clone/push operations, while `gh` CLI is still needed for API calls (repo listing, org membership, GraphQL).

Also check if the personal account (NEW_NAME, gathered in next step) is already on `gh auth`. If only one account is logged in, note that the personal account may need to be added later for org invitation acceptance.

### Step 2: Gather parameters

Now ask the user for the following using AskUserQuestion or by reading their message. Use the detected auth context to pre-fill or suggest values where possible (e.g., the active account's email as OLD_EMAIL):

- **ORG**: GitHub organization name (e.g., `myorg`)
- **OLD_EMAIL**: The current commit author email to replace (e.g., `work@company.com`)
- **NEW_NAME**: The new author name / GitHub username to migrate contributions to (e.g., `username`)
- **NEW_EMAIL**: The new author email — must be verified on the target GitHub account (e.g., `personal@gmail.com`)
- **SINCE_DATE**: Start date in `YYYY-MM-DD` format (e.g., `2025-01-01`)
- **UNTIL_DATE**: End date in `YYYY-MM-DD` format (e.g., `2026-01-01`). Commits ON this date are excluded.

Optional:
- **GIT_HOST**: GitHub hostname (default: `github.com`). For GitHub Enterprise, e.g., `github.mycompany.com`. Detected from `gh auth status` output.
- **SKIP_REPOS**: Comma-separated list of repos to skip (default: none)
- **DRY_RUN**: If true, rewrite but don't push (default: false)

### Step 3: Verify prerequisites

Run all checks below. Handle each failure before proceeding.

#### 3a. Check org membership

```bash
gh api "orgs/ORG/members/NEW_NAME" 2>&1
```

If the target account is already a member → proceed to 3b.

If NOT a member, run the full invite-and-accept flow:

**Invite** (using the work account, which should be active):
```bash
USER_ID=$(gh api "users/NEW_NAME" --jq '.id')
gh api -X POST "orgs/ORG/invitations" -F invitee_id=$USER_ID -f role=member
```

If inviting fails due to missing `admin:org` scope, re-auth and retry:
```bash
gh auth login -h GIT_HOST -s admin:org,repo --web
# Then retry the invite commands above
```

**Accept the invitation** (must switch to the personal account):

First check if the personal account is on gh CLI:
```bash
gh auth status 2>&1 | grep -c "NEW_NAME"
```

If the personal account is NOT on gh CLI, add it (this requires manual browser auth):
```bash
gh auth login -h GIT_HOST -s repo,read:org --web
# User completes browser OAuth for their personal account
```

Then switch to the personal account and accept:
```bash
gh auth switch -u NEW_NAME
gh api -X PATCH "user/memberships/orgs/ORG" -f state=active
```

Verify acceptance succeeded:
```bash
gh api "user/memberships/orgs/ORG" --jq '.state'
# Should output: "active"
```

Switch back to the work account for the remaining steps:
```bash
gh auth switch -u WORK_ACCOUNT
```

#### 3b. Confirm email verification

Run this to check if the target account exists and is valid:
```bash
gh api "users/NEW_NAME" --jq '{login, email, id}'
```

Remind the user:
- NEW_EMAIL must be a **verified email** on the target GitHub account
- Check at: `https://GIT_HOST/settings/emails` (while logged in as the personal account)
- GitHub only counts contributions for verified emails
- This cannot be checked via API — the user must confirm it themselves

### Step 4: Generate and run the script

Run the script with the user's parameters in the background. Include `--ssh-host` if SSH was detected/selected in Step 1:

```bash
# Build the command with all determined parameters.
# Include --ssh-host if SSH was detected in Step 1.
# Include --git-host if not github.com (e.g., GitHub Enterprise).
# Include --skip and --dry-run if user requested them.
nohup bash ~/.claude/commands/git-author-update.sh \
  --org "ORG" \
  --old-email "OLD_EMAIL" \
  --new-name "NEW_NAME" \
  --new-email "NEW_EMAIL" \
  --since "SINCE_DATE" \
  --until "UNTIL_DATE" \
  --ssh-host "SSH_HOST" \
  --git-host "GIT_HOST" \
  > /dev/null 2>&1 &
echo "PID: $!"
```

Find the log file:
```bash
ls -t /tmp/git-author-update-*/batch.log | head -1
```

### Step 5: Monitor progress

Periodically check the log file (every 30-60 seconds, longer for large repos):
```bash
tail -20 /tmp/git-author-update-*/batch.log
```

Wait until you see the final `DONE:` summary line.

### Step 6: Verify results

After completion, check contribution count via GitHub GraphQL:
```bash
gh api graphql -f query='{
  user(login: "NEW_NAME") {
    contributionsCollection(from: "SINCE_DATET00:00:00Z", to: "UNTIL_DATET00:00:00Z") {
      contributionCalendar { totalContributions }
      restrictedContributionsCount
      totalCommitContributions
    }
  }
}'
```

Report the results to the user. Note: GitHub may take ~30 minutes to fully reflect changes on the contribution graph.

## Manual steps (requires user browser interaction)

The entire flow is automated by Claude Code **except** these steps which require browser-based GitHub OAuth:

1. **`gh auth login`** — When the work account or personal account is not yet on the gh CLI, the user must complete OAuth in their browser. Claude will guide them through it.
2. **Email verification** — The user must confirm their personal email is verified at `GIT_HOST/settings/emails`. Claude cannot check or do this via API.

Everything else (account switching, org invitation, invitation acceptance, script execution, monitoring, verification) is fully automated.

## Important notes

- This rewrites git history and force-pushes. **It is irreversible.**
- Only commits within the date range AND matching the old email are changed.
- `git filter-branch` processes ALL commits in a repo, so large repos (10k+ commits) can take 10-20 minutes each.
- macOS and Linux compatible (uses `grep -oE`, avoids GNU-only syntax).
- The script also removes any `Co-authored-by` lines matching the new author (cleanup).
- Repos with branch protection rules may fail on push — logged as FAILED.
- `Co-authored-by` trailers do NOT produce GitHub green squares. You must change the actual `GIT_AUTHOR_EMAIL`.
- The target email must be a verified email on the GitHub account for contributions to count.
- The target account must be a member of the org for private repo contributions to appear.
- `gh api` uses `-f` for string parameters, `-F` for integer parameters (e.g., `invitee_id`).

$ARGUMENTS
