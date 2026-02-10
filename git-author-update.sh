#!/bin/bash
set -eo pipefail

# ============================================================
# Git Author Batch Update Script
# Rewrites commit author across all repos in a GitHub org.
# Changes GIT_AUTHOR_EMAIL/NAME for contribution graph visibility.
#
# Usage:
#   bash git-author-update.sh \
#     --org "myorg" \
#     --old-email "work@company.com" \
#     --new-name "username" \
#     --new-email "personal@gmail.com" \
#     --since "2025-01-01" \
#     --until "2026-01-01" \
#     [--skip "repo1,repo2"] \
#     [--dry-run]
#
# Prerequisites:
#   - gh CLI authenticated with push access to the org
#   - NEW_EMAIL must be verified on the target GitHub account
#   - Target account should be a member of the org (for private repos)
#
# Notes:
#   - macOS and Linux compatible
#   - Commits ON the until-date are excluded
#   - Large repos take longer (filter-branch processes all commits)
# ============================================================

# --- Parse Arguments ---
ORG=""
OLD_EMAIL=""
NEW_NAME=""
NEW_EMAIL=""
SINCE_DATE=""
UNTIL_DATE=""
SKIP_REPOS_CSV=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org)       ORG="$2"; shift 2 ;;
    --old-email) OLD_EMAIL="$2"; shift 2 ;;
    --new-name)  NEW_NAME="$2"; shift 2 ;;
    --new-email) NEW_EMAIL="$2"; shift 2 ;;
    --since)     SINCE_DATE="$2"; shift 2 ;;
    --until)     UNTIL_DATE="$2"; shift 2 ;;
    --skip)      SKIP_REPOS_CSV="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=true; shift ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: bash $0 --org ORG --old-email EMAIL --new-name NAME --new-email EMAIL --since YYYY-MM-DD --until YYYY-MM-DD [--skip repo1,repo2] [--dry-run]" >&2
      exit 1
      ;;
  esac
done

# --- Validate ---
MISSING=()
[[ -z "$ORG" ]]        && MISSING+=("--org")
[[ -z "$OLD_EMAIL" ]]  && MISSING+=("--old-email")
[[ -z "$NEW_NAME" ]]   && MISSING+=("--new-name")
[[ -z "$NEW_EMAIL" ]]  && MISSING+=("--new-email")
[[ -z "$SINCE_DATE" ]] && MISSING+=("--since")
[[ -z "$UNTIL_DATE" ]] && MISSING+=("--until")

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "Error: Missing required arguments: ${MISSING[*]}" >&2
  echo "Usage: bash $0 --org ORG --old-email EMAIL --new-name NAME --new-email EMAIL --since YYYY-MM-DD --until YYYY-MM-DD [--skip repo1,repo2] [--dry-run]" >&2
  exit 1
fi

# --- Configuration ---
WORK_DIR="/tmp/git-author-update-$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$WORK_DIR/batch.log"
AUTO_PUSH=true
CLEANUP=true
[[ "$DRY_RUN" = true ]] && AUTO_PUSH=false

# Parse skip list
IFS=',' read -ra SKIP_REPOS <<< "$SKIP_REPOS_CSV"

# --- Functions ---
log() { echo "[$(date +%H:%M:%S)] $*" >> "$LOG_FILE"; }

should_skip() {
  local repo="$1"
  for skip in "${SKIP_REPOS[@]}"; do
    [[ "$repo" == "$skip" ]] && return 0
  done
  return 1
}

rewrite_repo() {
  local repo_dir="$1"
  cd "$repo_dir"

  export OLD_EMAIL NEW_NAME NEW_EMAIL SINCE_DATE UNTIL_DATE

  FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch --force \
    --env-filter '
      if [ "$GIT_AUTHOR_EMAIL" = "$OLD_EMAIL" ]; then
        ISO_DATE=$(echo "$GIT_AUTHOR_DATE" | grep -oE "[0-9]{4}-[0-9]{2}-[0-9]{2}" | head -1)
        if [ -z "$ISO_DATE" ]; then
          TS=$(echo "$GIT_AUTHOR_DATE" | grep -oE "^@[0-9]+" | tr -d @)
          if [ -n "$TS" ]; then
            ISO_DATE=$(date -r "$TS" +%Y-%m-%d 2>/dev/null || date -d "@$TS" +%Y-%m-%d 2>/dev/null)
          fi
        fi
        if [ -n "$ISO_DATE" ] && [[ ! "$ISO_DATE" < "$SINCE_DATE" ]] && [[ "$ISO_DATE" < "$UNTIL_DATE" ]]; then
          export GIT_AUTHOR_NAME="$NEW_NAME"
          export GIT_AUTHOR_EMAIL="$NEW_EMAIL"
        fi
      fi
    ' \
    --msg-filter '
      grep -v "^Co-authored-by: '"$NEW_NAME"' <'"$NEW_EMAIL"'>$" || true
    ' \
    -- --all >/dev/null 2>&1
}

# --- Main ---
mkdir -p "$WORK_DIR"
touch "$LOG_FILE"

log "=== Git Author Batch Update ==="
log "Org: $ORG"
log "From: $OLD_EMAIL -> To: $NEW_NAME <$NEW_EMAIL>"
log "Date range: $SINCE_DATE to $UNTIL_DATE"
log "Auto-push: $AUTO_PUSH | Dry-run: $DRY_RUN | Cleanup: $CLEANUP"
[[ ${#SKIP_REPOS[@]} -gt 0 ]] && log "Skip repos: ${SKIP_REPOS[*]}"

REPOS=$(gh repo list "$ORG" --limit 1000 --json name --jq '.[].name')
REPO_COUNT=$(echo "$REPOS" | wc -l | tr -d ' ')
log "Found $REPO_COUNT repositories"

UPDATED=0
SKIPPED=0
FAILED=0
FAILED_REPOS=()
TOTAL_COMMITS=0
CURRENT=0

for REPO_NAME in $REPOS; do
  CURRENT=$((CURRENT + 1))

  if should_skip "$REPO_NAME"; then
    log "[$CURRENT/$REPO_COUNT] $REPO_NAME — SKIP (skip list)"
    continue
  fi

  log "[$CURRENT/$REPO_COUNT] $REPO_NAME — cloning..."

  REPO_DIR="$WORK_DIR/$REPO_NAME"
  if ! git clone --quiet "https://github.com/$ORG/$REPO_NAME.git" "$REPO_DIR" 2>/dev/null; then
    log "[$CURRENT/$REPO_COUNT] $REPO_NAME — FAILED (clone)"
    FAILED=$((FAILED + 1))
    FAILED_REPOS+=("$REPO_NAME")
    continue
  fi

  COMMIT_COUNT=$(cd "$REPO_DIR" && git log --all --author="$OLD_EMAIL" --since="$SINCE_DATE" --until="$UNTIL_DATE" --oneline 2>/dev/null | wc -l | tr -d ' ')

  if [ "$COMMIT_COUNT" -eq 0 ]; then
    log "[$CURRENT/$REPO_COUNT] $REPO_NAME — skip (0 commits)"
    SKIPPED=$((SKIPPED + 1))
    rm -rf "$REPO_DIR"
    continue
  fi

  log "[$CURRENT/$REPO_COUNT] $REPO_NAME — rewriting $COMMIT_COUNT commits..."

  if rewrite_repo "$REPO_DIR"; then
    if [ "$AUTO_PUSH" = "true" ]; then
      cd "$REPO_DIR"
      if git push --force --all 2>/dev/null && git push --force --tags 2>/dev/null; then
        log "[$CURRENT/$REPO_COUNT] $REPO_NAME — DONE ($COMMIT_COUNT commits)"
        UPDATED=$((UPDATED + 1))
        TOTAL_COMMITS=$((TOTAL_COMMITS + COMMIT_COUNT))
        [[ "$CLEANUP" = "true" ]] && rm -rf "$REPO_DIR"
      else
        log "[$CURRENT/$REPO_COUNT] $REPO_NAME — FAILED (push)"
        FAILED=$((FAILED + 1))
        FAILED_REPOS+=("$REPO_NAME")
      fi
    else
      log "[$CURRENT/$REPO_COUNT] $REPO_NAME — REWRITTEN (dry-run, $COMMIT_COUNT commits)"
      UPDATED=$((UPDATED + 1))
      TOTAL_COMMITS=$((TOTAL_COMMITS + COMMIT_COUNT))
    fi
  else
    log "[$CURRENT/$REPO_COUNT] $REPO_NAME — FAILED (rewrite)"
    FAILED=$((FAILED + 1))
    FAILED_REPOS+=("$REPO_NAME")
  fi

  cd /tmp
done

log ""
log "========================================"
log "DONE: $UPDATED repos ($TOTAL_COMMITS commits) | SKIP: $SKIPPED | FAIL: $FAILED"
if [ ${#FAILED_REPOS[@]} -gt 0 ]; then
  log "Failed: ${FAILED_REPOS[*]}"
fi
log "Log: $LOG_FILE"
