#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${CLAUDE_IMAGE:-claude-code}"
CONTAINER_LABEL="app=claude-code"
HOME_VOLUME="${CLAUDE_HOME_VOLUME:-claude-home}"
MEMORY_FILE="${CLAUDE_MEMORY_FILE:-$SCRIPT_DIR/claude/CLAUDE.md}"
WORKSPACE="$(cd "${CLAUDE_WORKSPACE:-$PWD}" && pwd)"
WORKSPACE_LABEL="claude-code.workspace=$WORKSPACE"
SHELL_MODE=false
REBUILD=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [--shell] [--rebuild]

Attaches to the running Claude Code container for the current directory,
offers to resume the most recently stopped one, or starts a new one. The
current directory is mounted at /src.

Options:
  -s, --shell    Open a bash shell in the container instead of Claude Code.
                 Claude Code keeps running in the background.
  -r, --rebuild  Offer to rebuild the image with the latest Claude Code release,
                 tagged as both $IMAGE:<version> and $IMAGE:latest, then continue.
                 Existing containers keep the image they were created from.
  -h, --help     Show this help.
EOF
}

while (($#)); do
  case "$1" in
    -s | --shell) SHELL_MODE=true ;;
    -r | --rebuild) REBUILD=true ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac
  shift
done

newest_container_with_status() {
  docker ps --all --latest --quiet --filter "label=$CONTAINER_LABEL" --filter "label=$WORKSPACE_LABEL" --filter "status=$1"
}

user_confirms() {
  local answer
  read -r -p "$1 [Y/n] " answer
  [[ -z "$answer" || "$answer" =~ ^[Yy] ]]
}

latest_claude_code_version() {
  local version
  version="$(
    curl --fail --silent --show-error --location \
      https://registry.npmjs.org/-/package/@anthropic-ai/claude-code/dist-tags |
      sed -nE 's/.*"latest":"([^"]+)".*/\1/p'
  )"
  if [[ -z "$version" ]]; then
    echo "Could not determine the latest Claude Code version from the npm registry." >&2
    exit 1
  fi
  echo "$version"
}

build_image() {
  local version="$1"
  echo "Building $IMAGE:$version from $SCRIPT_DIR..."
  docker build \
    --build-arg "CLAUDE_CODE_VERSION=$version" \
    --tag "$IMAGE:$version" \
    --tag "$IMAGE:latest" \
    "$SCRIPT_DIR"
}

ensure_image_exists() {
  if docker image inspect "$IMAGE" >/dev/null 2>&1; then
    return
  fi
  local version
  version="$(latest_claude_code_version)"
  if ! user_confirms "Image '$IMAGE' not found. Build it with Claude Code $version?"; then
    echo "Cannot start a container without an image." >&2
    exit 1
  fi
  build_image "$version"
}

offer_rebuild() {
  local version
  version="$(latest_claude_code_version)"
  if user_confirms "Rebuild $IMAGE with Claude Code $version?"; then
    build_image "$version"
  fi
}

open_shell_in() {
  exec docker exec --interactive --tty "$1" bash
}

start_new_container() {
  if [[ ! -f "$MEMORY_FILE" ]]; then
    echo "Memory file not found: $MEMORY_FILE" >&2
    exit 1
  fi
  ensure_image_exists
  echo "Starting a new Claude Code container for $WORKSPACE..."
  local run_options=(
    --interactive --tty
    --label "$CONTAINER_LABEL"
    --label "$WORKSPACE_LABEL"
    --volume "$HOME_VOLUME:/root/.claude"
    --volume "$MEMORY_FILE:/root/.claude/CLAUDE.md:ro"
    --volume "$WORKSPACE:/src"
  )
  if $SHELL_MODE; then
    open_shell_in "$(docker run --detach "${run_options[@]}" "$IMAGE")"
  fi
  exec docker run "${run_options[@]}" "$IMAGE"
}

describe_container() {
  docker inspect --format '{{.Name}} (created {{.Created}}, workspace {{range .Mounts}}{{if eq .Destination "/src"}}{{.Source}}{{end}}{{end}})' "$1" | sed 's|^/||'
}

if $REBUILD; then
  offer_rebuild
fi

running_container="$(newest_container_with_status running)"
if [[ -n "$running_container" ]]; then
  if $SHELL_MODE; then
    echo "Opening a shell in running container $(describe_container "$running_container")"
    open_shell_in "$running_container"
  fi
  echo "Attaching to running container $(describe_container "$running_container")"
  echo "Detach with Ctrl-P Ctrl-Q. Press Enter if the screen stays blank."
  exec docker attach "$running_container"
fi

stopped_container="$(newest_container_with_status exited)"
if [[ -z "$stopped_container" ]]; then
  stopped_container="$(newest_container_with_status created)"
fi
if [[ -n "$stopped_container" ]]; then
  echo "Found stopped container $(describe_container "$stopped_container")"
  if user_confirms "Resume it?"; then
    if $SHELL_MODE; then
      docker start "$stopped_container" >/dev/null
      open_shell_in "$stopped_container"
    fi
    exec docker start --attach --interactive "$stopped_container"
  fi
fi

start_new_container
