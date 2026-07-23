#!/usr/bin/env bash
# workspace-sync.sh — Scan workspace and git-update all repositories
#
# Iterates over all first-level subdirectories in the current project
# directory (the project root), identifies git repos, and
# pulls the latest changes for each one.
#
# When a branch tracks a remote ref that has been deleted (e.g. merged
# and cleaned up), the script auto-recovers by switching to the repo's
# default branch. Use --no-recover to disable this.
#
# Usage (invoked by /sdlc-workspace-sync skill):
#   workspace-sync.sh /path/to/project                # pull all repos
#   workspace-sync.sh /path/to/project --fetch-only    # fetch without merging
#   workspace-sync.sh /path/to/project --status         # show status only
#   workspace-sync.sh /path/to/project --no-recover     # don't auto-switch stale branches

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  BOLD='\033[1m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  RED='\033[0;31m'
  CYAN='\033[0;36m'
  DIM='\033[2m'
  RESET='\033[0m'
else
  BOLD="" GREEN="" YELLOW="" RED="" CYAN="" DIM="" RESET=""
fi

# ─── Resolve scan directory ──────────────────────────────────────────
# First positional arg is the project root (passed by the skill).
# Fallback to $PWD if not provided.
SCAN_DIR=""

# ─── Parse flags ──────────────────────────────────────────────────────
MODE="pull"  # pull | fetch | status
RECOVER=true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fetch-only)  MODE="fetch"; shift ;;
    --status)      MODE="status"; shift ;;
    --no-recover)  RECOVER=false; shift ;;
    -h|--help)
      echo "Usage: workspace-sync.sh [PROJECT_DIR] [--fetch-only | --status] [--no-recover]"
      echo ""
      echo "  PROJECT_DIR     Project root directory (default: \$PWD)"
      echo "  (default)       Pull latest changes on each repo's current branch"
      echo "  --fetch-only    Fetch from remotes without merging"
      echo "  --status        Show repo status only (no network operations)"
      echo "  --no-recover    Don't auto-switch stale branches to default"
      echo ""
      echo "Scans all first-level git subdirectories in the project root."
      exit 0
      ;;
    *)
      # First non-flag argument is the project directory
      if [[ -z "$SCAN_DIR" && -d "$1" ]]; then
        SCAN_DIR="$1"; shift
      else
        echo -e "${RED}Unknown flag:${RESET} $1"; exit 1
      fi
      ;;
  esac
done

# Default to PWD if no project dir was provided
SCAN_DIR="${SCAN_DIR:-$PWD}"

# ─── Helpers ──────────────────────────────────────────────────────────

# Detect the default branch for a repo (main, master, etc.)
default_branch() {
  local dir="$1"
  # Try symbolic-ref first (most reliable after a fetch)
  local ref
  ref="$(git -C "$dir" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -n "$ref" ]]; then
    echo "${ref#refs/remotes/origin/}"
    return
  fi
  # Fallback: check for common names
  for candidate in main master develop; do
    if git -C "$dir" rev-parse --verify "origin/$candidate" &>/dev/null; then
      echo "$candidate"
      return
    fi
  done
  echo ""
}

# Classify a pull/rebase error from stderr
classify_error() {
  local stderr="$1"
  if echo "$stderr" | grep -qi "no such ref was fetched"; then
    echo "stale_upstream"
  elif echo "$stderr" | grep -qi "CONFLICT\|could not apply\|Failed to merge"; then
    echo "merge_conflict"
  elif echo "$stderr" | grep -qi "Could not resolve host\|unable to access\|Connection refused"; then
    echo "network_error"
  else
    echo "unknown"
  fi
}

# ─── Discover git repos ──────────────────────────────────────────────
REPOS=()
for dir in "$SCAN_DIR"/*/; do
  [[ -d "$dir/.git" ]] && REPOS+=("$dir")
done

if [[ ${#REPOS[@]} -eq 0 ]]; then
  echo -e "${YELLOW}No git repositories found in ${SCAN_DIR}${RESET}"
  exit 0
fi

# ─── Header ───────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Workspace Sync${RESET}  ${DIM}(${SCAN_DIR})${RESET}"
echo -e "${DIM}$(printf '─%.0s' {1..60})${RESET}"
echo -e "  Repositories: ${#REPOS[@]}"
echo -e "  Mode:         ${CYAN}${MODE}${RESET}"
echo -e "${DIM}$(printf '─%.0s' {1..60})${RESET}"
echo ""

# ─── Counters ─────────────────────────────────────────────────────────
OK=0
SKIPPED=0
FAILED=0
UPDATED=0
RECOVERED=0

# ─── Process each repository ─────────────────────────────────────────
for repo_dir in "${REPOS[@]}"; do
  repo_name="$(basename "$repo_dir")"

  printf "  %-30s " "$repo_name"

  # Get current branch
  branch="$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")"

  # ── Status mode ──────────────────────────────────────────────────
  if [[ "$MODE" == "status" ]]; then
    dirty="$(git -C "$repo_dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    behind="$(git -C "$repo_dir" rev-list --count HEAD..@{upstream} 2>/dev/null || echo "?")"
    ahead="$(git -C "$repo_dir" rev-list --count @{upstream}..HEAD 2>/dev/null || echo "?")"

    status_parts=()
    [[ "$dirty" != "0" ]] && status_parts+=("${YELLOW}${dirty} dirty${RESET}")
    [[ "$ahead" != "0" && "$ahead" != "?" ]] && status_parts+=("${CYAN}${ahead} ahead${RESET}")
    [[ "$behind" != "0" && "$behind" != "?" ]] && status_parts+=("${YELLOW}${behind} behind${RESET}")

    if [[ ${#status_parts[@]} -eq 0 ]]; then
      echo -e "${GREEN}OK${RESET}    ${DIM}($branch)${RESET}"
    else
      echo_parts="${status_parts[*]}"
      echo -e "${GREEN}OK${RESET}    ${DIM}($branch)${RESET}  $echo_parts"
    fi
    ((OK++))
    continue
  fi

  # ── Fetch first (prune stale remote refs) ────────────────────────
  fetch_err=""
  if ! fetch_err="$(git -C "$repo_dir" fetch --all --prune 2>&1)"; then
    error_type="$(classify_error "$fetch_err")"
    echo -e "${RED}FAIL${RESET}  ${DIM}($branch — ${error_type//_/ })${RESET}"
    ((FAILED++))
    continue
  fi

  # ── Fetch-only mode ──────────────────────────────────────────────
  if [[ "$MODE" == "fetch" ]]; then
    echo -e "${GREEN}FETCH${RESET} ${DIM}($branch)${RESET}"
    ((OK++))
    continue
  fi

  # ── Check for uncommitted changes ────────────────────────────────
  dirty="$(git -C "$repo_dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$dirty" != "0" ]]; then
    echo -e "${YELLOW}DIRTY${RESET} ${DIM}($branch, $dirty uncommitted files — skipping pull)${RESET}"
    ((SKIPPED++))
    continue
  fi

  # ── Detect stale upstream ────────────────────────────────────────
  if ! git -C "$repo_dir" rev-parse --verify "@{upstream}" &>/dev/null; then
    if [[ "$RECOVER" == true ]]; then
      default="$(default_branch "$repo_dir")"
      if [[ -z "$default" ]]; then
        echo -e "${RED}FAIL${RESET}  ${DIM}($branch — stale upstream, no default branch found)${RESET}"
        ((FAILED++))
        continue
      fi
      before="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null)"
      if git -C "$repo_dir" checkout "$default" --quiet 2>/dev/null \
         && git -C "$repo_dir" pull --rebase --quiet 2>/dev/null; then
        after="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null)"
        if [[ "$before" != "$after" ]]; then
          commits="$(git -C "$repo_dir" rev-list --count "$before..$after" 2>/dev/null || echo "?")"
          echo -e "${CYAN}RECOVER${RESET} ${DIM}($branch → $default, +${commits} commits)${RESET}"
        else
          echo -e "${CYAN}RECOVER${RESET} ${DIM}($branch → $default, up to date)${RESET}"
        fi
        ((RECOVERED++))
      else
        echo -e "${RED}FAIL${RESET}  ${DIM}($branch — recovery to $default failed)${RESET}"
        ((FAILED++))
      fi
    else
      echo -e "${YELLOW}STALE${RESET} ${DIM}($branch — upstream deleted, use default branch manually)${RESET}"
      ((SKIPPED++))
    fi
    continue
  fi

  # ── Pull with rebase ─────────────────────────────────────────────
  before="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null)"
  pull_err=""
  if pull_err="$(git -C "$repo_dir" pull --rebase 2>&1)"; then
    after="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null)"
    if [[ "$before" != "$after" ]]; then
      commits="$(git -C "$repo_dir" rev-list --count "$before..$after" 2>/dev/null || echo "?")"
      echo -e "${GREEN}PULL${RESET}  ${DIM}($branch, +${commits} commits)${RESET}"
      ((UPDATED++))
    else
      echo -e "${GREEN}OK${RESET}    ${DIM}($branch, already up to date)${RESET}"
    fi
    ((OK++))
  else
    error_type="$(classify_error "$pull_err")"
    # Abort any in-progress rebase so the repo isn't left in a broken state
    git -C "$repo_dir" rebase --abort 2>/dev/null || true
    echo -e "${RED}FAIL${RESET}  ${DIM}($branch — ${error_type//_/ })${RESET}"
    ((FAILED++))
  fi
done

# ─── Summary ──────────────────────────────────────────────────────────
echo ""
echo -e "${DIM}$(printf '─%.0s' {1..60})${RESET}"
echo -e "  ${GREEN}OK: $OK${RESET}  ${CYAN}Recovered: $RECOVERED${RESET}  ${YELLOW}Skipped: $SKIPPED${RESET}  ${RED}Failed: $FAILED${RESET}  Updated: $UPDATED"
echo ""

[[ $FAILED -gt 0 ]] && exit 1
exit 0
