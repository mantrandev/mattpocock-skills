#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
claude_manifest="$repo_dir/.claude-plugin/plugin.json"
plugin_dir="$repo_dir/plugins/mattpocock-skills"
codex_manifest="$plugin_dir/.codex-plugin/plugin.json"
target_dir="$plugin_dir/skills"
staging_dir="$(mktemp -d)"
temp_manifest="$(mktemp)"
trap 'rm -rf "$staging_dir"; rm -f "$temp_manifest"' EXIT

expected_count=0
while IFS= read -r skill_md; do
  source_dir="$(dirname "$skill_md")"
  skill_name="$(basename "$source_dir")"
  if [ -e "$staging_dir/$skill_name" ]; then
    echo "Duplicate skill name across buckets: $skill_name" >&2
    exit 1
  fi
  cp -R "$source_dir" "$staging_dir/$skill_name"
  perl -0pi -e 's/^disable-model-invocation: true\R//m' "$staging_dir/$skill_name/SKILL.md"
  expected_count=$((expected_count + 1))
done < <(find "$repo_dir/skills" -mindepth 3 -maxdepth 3 -name SKILL.md -type f -not -path "*/deprecated/*" | sort)

if [ "$expected_count" -eq 0 ]; then
  echo "No skills found under $repo_dir/skills" >&2
  exit 1
fi

mkdir -p "$target_dir"
rsync -a --delete "$staging_dir/" "$target_dir/"

base_version="$(jq -r '.version' "$claude_manifest")"
base_version="${base_version%%+*}"
if ! revision="$(git -C "$repo_dir" rev-parse --short=12 upstream/main 2>/dev/null)"; then
  revision="$(git -C "$repo_dir" rev-parse --short=12 HEAD)"
fi
version="$base_version+codex.$revision"
jq --arg version "$version" '.version = $version' "$codex_manifest" > "$temp_manifest"
mv "$temp_manifest" "$codex_manifest"

actual_count="$(find "$target_dir" -mindepth 2 -maxdepth 2 -name SKILL.md -type f | wc -l | tr -d ' ')"
if [ "$actual_count" -ne "$expected_count" ]; then
  echo "Codex plugin skill count mismatch: expected $expected_count, got $actual_count" >&2
  exit 1
fi

echo "Codex plugin synchronized with $actual_count skills at version $version"
