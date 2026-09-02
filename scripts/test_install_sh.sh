#!/usr/bin/env bash
# Behavioural tests for Claude Code, Codex, and dual-agent vendoring.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALLER="$ROOT/install.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILURES=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { FAILURES=$((FAILURES + 1)); printf '  FAIL %s\n' "$1"; }

expect_file() {
  if [ -f "$1" ]; then ok "$2"; else bad "$2 (missing $1)"; fi
}

expect_absent() {
  if [ ! -e "$1" ]; then ok "$2"; else bad "$2 (unexpected $1)"; fi
}

expect_contains() {
  if grep -Fq "$2" "$1"; then ok "$3"; else bad "$3 (missing '$2' in $1)"; fi
}

expect_not_contains() {
  if grep -Fq "$2" "$1"; then bad "$3 (found '$2' in $1)"; else ok "$3"; fi
}

make_project() {
  local project="$1"
  mkdir -p "$project/lib"
  printf 'dependencies:\n  flutter:\n    sdk: flutter\n' > "$project/pubspec.yaml"
}

echo "== Codex project install =="
CODEX_PROJECT="$WORK/codex-project"
CODEX_TEST_HOME="$WORK/codex-home"
make_project "$CODEX_PROJECT"
FLUTTER_SKILLS_HOME="$CODEX_TEST_HOME" \
  bash "$INSTALLER" --codex --project "$CODEX_PROJECT" >/dev/null

expect_file "$CODEX_PROJECT/.agents/skills/design-tokens/SKILL.md" \
  "project skills use .agents/skills"
expect_file "$CODEX_PROJECT/.agents/skills/flutter-adapt/SKILL.md" \
  "flutter-adapt installs as a Codex skill"
expect_file "$CODEX_TEST_HOME/.agents/skills/review-gate/SKILL.md" \
  "machine-scoped Codex skills use the personal path"
expect_absent "$CODEX_PROJECT/.agents/skills/review-gate" \
  "machine-scoped skills are not copied into the project"
expect_absent "$CODEX_PROJECT/.claude" \
  "Codex-only install does not create Claude directories"

ADAPT="$CODEX_PROJECT/.agents/skills/flutter-adapt/SKILL.md"
expect_file "$CODEX_PROJECT/.agents/skills/flutter-adapt/references/flutter-profile.md" \
  "vendored cross-skill references are copied locally"
expect_contains "$ADAPT" 'references/flutter-profile.md' \
  "vendored skill points at its local profile reference"
expect_not_contains "$ADAPT" '../architecture/references/flutter-profile.md' \
  "vendored skill no longer depends on its sibling"

echo "== dual personal install =="
BOTH_TEST_HOME="$WORK/both-home"
FLUTTER_SKILLS_HOME="$BOTH_TEST_HOME" bash "$INSTALLER" --both --all-personal >/dev/null

for base in "$BOTH_TEST_HOME/.agents/skills" "$BOTH_TEST_HOME/.claude/skills"; do
  expect_file "$base/design-tokens/SKILL.md" "both installs design skills in $base"
  expect_file "$base/flutter-adapt/SKILL.md" "both installs flutter-adapt in $base"
  expect_file "$base/review-gate/SKILL.md" "both installs review-gate in $base"
done

echo "== Codex machine-only install =="
PERSONAL_TEST_HOME="$WORK/personal-home"
FLUTTER_SKILLS_HOME="$PERSONAL_TEST_HOME" bash "$INSTALLER" --codex --personal >/dev/null
expect_file "$PERSONAL_TEST_HOME/.agents/skills/performance/SKILL.md" \
  "--personal installs performance"
expect_file "$PERSONAL_TEST_HOME/.agents/skills/review-gate/SKILL.md" \
  "--personal installs review-gate"
expect_absent "$PERSONAL_TEST_HOME/.agents/skills/flutter-adapt" \
  "--personal omits project-scoped skills"

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "all installer tests passed"
  exit 0
fi
echo "$FAILURES installer test(s) failed"
exit 1
