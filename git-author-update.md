# Git Author Batch Update

Rewrite commit authors across all repositories in a GitHub organization. Changes `GIT_AUTHOR_EMAIL` and `GIT_AUTHOR_NAME` so commits appear on the target GitHub contribution graph ("grass").

## What this skill does

1. Clones all repositories from a GitHub org
2. Rewrites commit author for commits matching the old email within a date range
3. Force-pushes the rewritten history
4. Verifies contribution count via GitHub API

## Instructions

When the user invokes this skill, follow these steps:

### Step 1: Detect gh CLI auth context

Before asking anything, run `gh auth status` to detect the current GitHub CLI state. Present the results to the user:

```bash
gh auth status
```

Show the user:
- Which account(s) are logged in
- Which account is currently active
- What token scopes are available

Then confirm with the user:
- Is the **active account** the one with push access to the org? (It should be the org/work account, not the personal one.)
- If multiple accounts exist, ask which one should be used for pushing.
- If no account is logged in, instruct them to run `gh auth login`.
- If the active account lacks required scopes (`repo`), instruct them to re-auth: `gh auth login -h github.com -s repo --web`

**Important:** The active `gh` account must have push access to the org repos. This is typically the work/org account, NOT the personal account they want contributions migrated to.

### Step 2: Gather parameters

Now ask the user for the following using AskUserQuestion or by reading their message. Use the detected auth context to pre-fill or suggest values where possible (e.g., the active account's email as OLD_EMAIL):

- **ORG**: GitHub organization name (e.g., `myorg`)
- **OLD_EMAIL**: The current commit author email to replace (e.g., `work@company.com`)
- **NEW_NAME**: The new author name / GitHub username to migrate contributions to (e.g., `username`)
- **NEW_EMAIL**: The new author email — must be verified on the target GitHub account (e.g., `personal@gmail.com`)
- **SINCE_DATE**: Start date in `YYYY-MM-DD` format (e.g., `2025-01-01`)
- **UNTIL_DATE**: End date in `YYYY-MM-DD` format (e.g., `2026-01-01`). Commits ON this date are excluded.

Optional:
- **SKIP_REPOS**: Comma-separated list of repos to skip (default: none)
- **DRY_RUN**: If true, rewrite but don't push (default: false)

### Step 3: Verify prerequisites

Check these before running:

```bash
# 1. Verify the target account (NEW_NAME) is a member of the org
#    (required for private repo contributions to appear on the graph)
gh api "orgs/ORG/members/NEW_NAME" 2>&1
```

If the target account is NOT a member of the org, offer to invite them:
```bash
# Get user ID
USER_ID=$(gh api "users/NEW_NAME" --jq '.id')
# Invite (requires admin:org scope on the active account)
gh api -X POST "orgs/ORG/invitations" -F invitee_id=$USER_ID -f role=member
```

If inviting fails due to missing `admin:org` scope, instruct the user:
```bash
gh auth login -h github.com -s admin:org,repo --web
```

Also remind the user:
- The NEW_EMAIL must be a **verified email** on the target GitHub account (check at https://github.com/settings/emails)
- GitHub only counts contributions for verified emails

### Step 4: Generate and run the script

Run the script with the user's parameters in the background:

```bash
nohup bash ~/.claude/commands/git-author-update.sh \
  --org "ORG" \
  --old-email "OLD_EMAIL" \
  --new-name "NEW_NAME" \
  --new-email "NEW_EMAIL" \
  --since "SINCE_DATE" \
  --until "UNTIL_DATE" \
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

$ARGUMENTS
