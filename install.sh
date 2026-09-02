#!/usr/bin/env bash
# Vendor the skills directly into a project or into a personal skills directory,
# as an alternative to installing through a Claude Code or Codex marketplace.
#
# Marketplace install (recommended):
#   claude plugin marketplace add draz26648/flutter-craft-skills
#   claude plugin install flutter-design-fidelity@flutter-craft-skills
#   claude plugin install flutter-code-quality@flutter-craft-skills
#
# Codex marketplace install:
#   codex plugin marketplace add draz26648/flutter-craft-skills
#   codex plugin add flutter-design-fidelity@flutter-craft-skills
#   codex plugin add flutter-code-quality@flutter-craft-skills

set -euo pipefail

PROJECT=""
PERSONAL_ONLY=false
ALL_PERSONAL=false
FORCE=false
AGENT=claude

usage() {
  cat <<USAGE
Usage: ./install.sh [options]

  --project <path>   Copy project-scoped skills into the selected agent's project path
  --personal         Copy only the machine-scoped skills into the personal path
  --all-personal     Copy every skill into the personal path
  --claude           Install for Claude Code (default)
  --codex            Install for Codex
  --both             Install for both Claude Code and Codex
  --force            Overwrite skills that are already installed
  -h, --help         Show this message

Without --force an already-installed skill is left alone, so local edits survive.
That also means it never updates — re-run with --force to take a new version, and
diff first if you have adapted it.

Claude Code uses `.claude/skills` and `~/.claude/skills`. Codex uses `.agents/skills`
and `~/.agents/skills`. With --project, the machine-scoped skills (performance,
review-gate) also go to the selected personal path so they follow you across projects.

Vendoring is the right choice when you want the skills committed to the repo and
reviewable in pull requests alongside the code they govern. Otherwise prefer the
marketplace, which gives you updates.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --personal) PERSONAL_ONLY=true; shift ;;
    --all-personal) ALL_PERSONAL=true; shift ;;
    --claude) AGENT=claude; shift ;;
    --codex) AGENT=codex; shift ;;
    --both) AGENT=both; shift ;;
    --force) FORCE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")" && pwd)"
DESIGN="$ROOT/plugins/flutter-design-fidelity/skills"
QUALITY="$ROOT/plugins/flutter-code-quality/skills"
PROFILE_SPEC="$QUALITY/architecture/references/flutter-profile.md"
PERSONAL_ROOT="${FLUTTER_SKILLS_HOME:-$HOME}"

# Cross-skill links work while a whole plugin is installed, but not when the skills are
# vendored independently. Give each vendored skill its own copy of the shared spec.
localise_profile_link() {
  local skill_dir="$1" md="$1/SKILL.md"
  [ -f "$md" ] || return 0
  grep -Eq '\.\./[a-z-]+/references/flutter-profile\.md' "$md" || return 0
  mkdir -p "$skill_dir/references"
  cp "$PROFILE_SPEC" "$skill_dir/references/flutter-profile.md"
  sed -E 's|\.\./[a-z-]+/references/flutter-profile\.md|references/flutter-profile.md|g' \
    "$md" > "$md.tmp" && mv "$md.tmp" "$md"
}

copy_skill() {
  local src="$1" dest="$2" name
  name="$(basename "$src")"
  if [ -d "$dest/$name" ]; then
    if [ "$FORCE" = true ]; then
      rm -rf "${dest:?}/${name:?}"
      cp -r "$src" "$dest/"
      localise_profile_link "$dest/$name"
      echo "  updated $name"
    else
      echo "  skip $name (already installed — re-run with --force to update)"
    fi
  else
    cp -r "$src" "$dest/"
    localise_profile_link "$dest/$name"
    echo "  added $name"
  fi
}

project_skills() {
  echo "$DESIGN/design-tokens $DESIGN/figma-to-widget $DESIGN/visual-verification $DESIGN/golden-tests $QUALITY/architecture $QUALITY/state-management $QUALITY/responsive-adaptive $QUALITY/a11y-and-rtl $QUALITY/codebase-conventions $QUALITY/flutter-adapt"
}

personal_skills() {
  echo "$QUALITY/performance $QUALITY/review-gate"
}

install_for_agent() {
  local agent="$1" project_dest personal_dest invocation
  case "$agent" in
    claude)
      project_dest="$PROJECT/.claude/skills"
      personal_dest="$PERSONAL_ROOT/.claude/skills"
      invocation="/flutter-code-quality:flutter-adapt"
      ;;
    codex)
      project_dest="$PROJECT/.agents/skills"
      personal_dest="$PERSONAL_ROOT/.agents/skills"
      invocation='$flutter-adapt'
      ;;
  esac

  if [ "$ALL_PERSONAL" = true ]; then
    echo "Copying all skills for $agent to $personal_dest/"
    mkdir -p "$personal_dest"
    for s in $(project_skills) $(personal_skills); do copy_skill "$s" "$personal_dest"; done

  elif [ "$PERSONAL_ONLY" = true ]; then
    echo "Copying machine-scoped skills for $agent to $personal_dest/"
    mkdir -p "$personal_dest"
    for s in $(personal_skills); do copy_skill "$s" "$personal_dest"; done
    echo "  note: flutter-adapt not installed — it needs the architecture skill, which"
    echo "        --personal does not copy. Use --project or --all-personal for it."

  elif [ -n "$PROJECT" ]; then
    echo "Copying project skills for $agent to $project_dest/"
    mkdir -p "$project_dest"
    for s in $(project_skills); do copy_skill "$s" "$project_dest"; done
    echo "Copying machine-scoped skills for $agent to $personal_dest/"
    mkdir -p "$personal_dest"
    for s in $(personal_skills); do copy_skill "$s" "$personal_dest"; done
  fi

  printf '  adapt with: %s\n' "$invocation"
}

if [ "$ALL_PERSONAL" != true ] && [ "$PERSONAL_ONLY" != true ] && [ -z "$PROJECT" ]; then
  usage
  exit 1
fi

if [ -n "$PROJECT" ]; then
  [ -f "$PROJECT/pubspec.yaml" ] || echo "Warning: no pubspec.yaml at $PROJECT — is that a Flutter project?"
fi

case "$AGENT" in
  claude|codex) install_for_agent "$AGENT" ;;
  both)
    install_for_agent claude
    install_for_agent codex
    ;;
esac

cat <<'NEXT'

Done.

Next:
  1. Restart the agent if its skills directory did not exist before.
  2. Verify the installed */skills/*/SKILL.md files.
  3. Run flutter-adapt to generate .agents/flutter-profile.yaml, so the skills describe
     your stack rather than the defaults they ship with.
NEXT
