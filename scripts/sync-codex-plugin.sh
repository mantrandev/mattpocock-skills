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

jq -r '.skills[]' "$claude_manifest" | while IFS= read -r relative_path; do
  source_dir="$repo_dir/${relative_path#./}"
  skill_name="$(basename "$source_dir")"
  if [ ! -f "$source_dir/SKILL.md" ]; then
    echo "Missing promoted skill: $relative_path" >&2
    exit 1
  fi
  cp -R "$source_dir" "$staging_dir/$skill_name"
  perl -0pi -e 's/^disable-model-invocation: true\R//m' "$staging_dir/$skill_name/SKILL.md"
done

mkdir -p "$target_dir"
rsync -a --delete "$staging_dir/" "$target_dir/"

version="$(jq -r '.version' "$claude_manifest")"
jq --arg version "$version" '.version = $version' "$codex_manifest" > "$temp_manifest"
mv "$temp_manifest" "$codex_manifest"

expected_count="$(jq '.skills | length' "$claude_manifest")"
actual_count="$(find "$target_dir" -mindepth 2 -maxdepth 2 -name SKILL.md -type f | wc -l | tr -d ' ')"
if [ "$actual_count" -ne "$expected_count" ]; then
  echo "Codex plugin skill count mismatch: expected $expected_count, got $actual_count" >&2
  exit 1
fi

echo "Codex plugin synchronized with $actual_count promoted skills at version $version"
