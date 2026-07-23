#!/usr/bin/env bash
set -euo pipefail

# bump-version.sh <plugin-name> <bump-type>
# Reads the current version from the plugin's plugin.json,
# applies a semver bump, writes it back, and outputs the new version.

PLUGIN="${1:?Usage: bump-version.sh <plugin> <patch|minor|major>}"
BUMP="${2:?Usage: bump-version.sh <plugin> <patch|minor|major>}"

PLUGIN_JSON="plugins/${PLUGIN}/.claude-plugin/plugin.json"

if [ ! -f "$PLUGIN_JSON" ]; then
  echo "::error::Plugin manifest not found: ${PLUGIN_JSON}"
  exit 1
fi

CURRENT=$(jq -r '.version' "$PLUGIN_JSON")
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

case "$BUMP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
  *) echo "::error::Invalid bump type: ${BUMP}. Must be patch, minor, or major."; exit 1 ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"

# Update plugin.json
jq --arg v "$NEW_VERSION" '.version = $v' "$PLUGIN_JSON" > tmp.$$.json && mv tmp.$$.json "$PLUGIN_JSON"

# Update marketplace.json plugin entry
MARKETPLACE_JSON=".claude-plugin/marketplace.json"
if [ ! -f "$MARKETPLACE_JSON" ]; then
  echo "::error::Marketplace manifest not found: ${MARKETPLACE_JSON}"
  exit 1
fi

MARKETPLACE_VERSION_BEFORE=$(jq -r --arg name "$PLUGIN" '.plugins[] | select(.name == $name).version' "$MARKETPLACE_JSON")
if [ -z "$MARKETPLACE_VERSION_BEFORE" ]; then
  echo "::error::Plugin '${PLUGIN}' not found in ${MARKETPLACE_JSON}"
  exit 1
fi

jq --arg name "$PLUGIN" --arg v "$NEW_VERSION" \
  '(.plugins[] | select(.name == $name)).version = $v' \
  "$MARKETPLACE_JSON" > tmp.$$.json && mv tmp.$$.json "$MARKETPLACE_JSON"
echo "Updated marketplace entry for ${PLUGIN} from ${MARKETPLACE_VERSION_BEFORE} to ${NEW_VERSION}"

echo "Bumped ${PLUGIN} from ${CURRENT} to ${NEW_VERSION}"
echo "new_version=${NEW_VERSION}" >> "$GITHUB_OUTPUT"
echo "old_version=${CURRENT}" >> "$GITHUB_OUTPUT"
