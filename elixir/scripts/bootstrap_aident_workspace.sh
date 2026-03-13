#!/usr/bin/env bash
set -u

log_file=".symphony-bootstrap.log"
tmp_log_file="$(mktemp /tmp/symphony-bootstrap.XXXXXX)"
active_log_file="$tmp_log_file"
repo_url="${AIDENT_SOURCE_REPO_URL:-https://github.com/Aident-AI/aident.ai}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
symphony_root="$(cd "$script_dir/../.." && pwd)"
stock_skill_root="$symphony_root/.codex/skills"
template_skill_root="$symphony_root/elixir/templates/aident/.codex/skills"

log() {
  printf '%s\n' "$*" | tee -a "$active_log_file"
}

run_step() {
  local label="$1"
  shift

  log ""
  log "==> $label"

  "$@" >>"$active_log_file" 2>&1
  local status=$?

  if [ "$status" -eq 0 ]; then
    log "ok: $label"
    return 0
  fi

  log "warn: $label failed with exit $status"
  return $status
}

run_shell_step() {
  local label="$1"
  shift
  run_step "$label" sh -lc "$*"
}

copy_skill() {
  local source_dir="$1"
  local skill_name="$2"
  local destination_dir=".codex/skills/$skill_name"

  rm -rf "$destination_dir"
  cp -R "$source_dir/$skill_name" "$destination_dir"
  log "installed skill: $skill_name"
}

if [ -n "$(find . -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
  log "workspace is not empty; skipping Aident bootstrap"
  rm -f "$tmp_log_file"
  exit 0
fi

if ! run_shell_step "clone aident.ai" "git clone --depth 1 \"$repo_url\" ."; then
  log "bootstrap stopped after clone failure"
  rm -f "$tmp_log_file"
  exit 0
fi

cp "$tmp_log_file" "$log_file"
rm -f "$tmp_log_file"
active_log_file="$log_file"

mkdir -p .codex/skills
copy_skill "$stock_skill_root" "linear"
copy_skill "$template_skill_root" "commit"
copy_skill "$template_skill_root" "push"
copy_skill "$template_skill_root" "pull"
copy_skill "$template_skill_root" "land"

if command -v gt >/dev/null 2>&1; then
  run_shell_step "initialize graphite for main trunk" "gt init --trunk main --no-interactive" || true
else
  log "warn: gt is not installed; Graphite-based push and merge flows will block"
fi

if command -v pnpm >/dev/null 2>&1; then
  run_shell_step "install workspace dependencies" "pnpm install --frozen-lockfile" || true
  run_shell_step "build shared package" "pnpm --filter @aident/shared build" || true
else
  log "warn: pnpm is not installed; dependency bootstrap skipped"
fi

log ""
log "bootstrap complete"
log "review $log_file before starting implementation work"
