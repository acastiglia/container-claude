#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${CLAUDE_IMAGE:-claude-code}"
CONTAINER_LABEL="app=claude-code"
HOME_VOLUME="${CLAUDE_HOME_VOLUME:-claude-home}"
MEMORY_FILE="${CLAUDE_MEMORY_FILE:-$HOME/.claude/CLAUDE.md}"
AGENTS_DIR="${CLAUDE_AGENTS_DIR:-$HOME/.claude/agents}"
MEMORY_FILE_EXPLICIT=false
[[ -n "${CLAUDE_MEMORY_FILE:-}" ]] && MEMORY_FILE_EXPLICIT=true
AGENTS_DIR_EXPLICIT=false
[[ -n "${CLAUDE_AGENTS_DIR:-}" ]] && AGENTS_DIR_EXPLICIT=true
GH_TOKEN_FILE="${CLAUDE_GH_TOKEN_FILE:-$HOME/.config/claude-code/gh-token}"
GH_TOKEN_FILE_EXPLICIT=false
[[ -n "${CLAUDE_GH_TOKEN_FILE:-}" ]] && GH_TOKEN_FILE_EXPLICIT=true
CONTAINER_GH_TOKEN_DIR=/run/secrets/claude-code
WORKSPACE="$(cd "${CLAUDE_WORKSPACE:-$PWD}" && pwd)"
WORKSPACE_LABEL="claude-code.workspace=$WORKSPACE"
SHELL_MODE=false
REBUILD=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [--shell] [--rebuild] [--memory-file FILE] [--agents-dir DIR]

Starts a Claude Code container for the current directory. If stopped
containers exist for the directory, offers a choice of resuming one of them
or starting a new one. Running containers are left alone, so each run starts
a separate Claude Code session. The current directory is mounted at /src.

Options:
  -s, --shell             Open a bash shell in the container instead of Claude Code.
                          Claude Code keeps running in the background. Running
                          containers are also offered.
  -r, --rebuild           Offer to rebuild the image with the latest Claude Code release,
                          tagged as both $IMAGE:<version> and $IMAGE:latest, then continue.
                          Existing containers keep the image they were created from.
  -m, --memory-file FILE  Mount FILE read-only as the global CLAUDE.md in new containers.
                          Defaults to ~/.claude/CLAUDE.md, mounted only if it exists.
                          Existing containers keep the memory file they were created with.
  -a, --agents-dir DIR    Mount DIR read-only as the global agents directory
                          (/root/.claude/agents) in new containers. Defaults to
                          ~/.claude/agents, mounted only if it exists. Existing
                          containers keep the agents directory they were created with.
  -h, --help              Show this help.
EOF
}

while (($#)); do
  case "$1" in
    -s | --shell) SHELL_MODE=true ;;
    -r | --rebuild) REBUILD=true ;;
    -m | --memory-file)
      if (($# < 2)); then
        usage >&2
        exit 1
      fi
      MEMORY_FILE="$2"
      MEMORY_FILE_EXPLICIT=true
      shift
      ;;
    -a | --agents-dir)
      if (($# < 2)); then
        usage >&2
        exit 1
      fi
      AGENTS_DIR="$2"
      AGENTS_DIR_EXPLICIT=true
      shift
      ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac
  shift
done

if [[ "${IMAGE##*/}" == *:* ]]; then
  echo "CLAUDE_IMAGE must be an image name without a tag: $IMAGE" >&2
  exit 1
fi

containers_with_status() {
  local status_filters=()
  local status
  for status in "$@"; do
    status_filters+=(--filter "status=$status")
  done
  docker ps --all --quiet --filter "label=$CONTAINER_LABEL" --filter "label=$WORKSPACE_LABEL" "${status_filters[@]}"
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
  local run_options=(
    --interactive --tty
    --label "$CONTAINER_LABEL"
    --label "$WORKSPACE_LABEL"
    --volume "$HOME_VOLUME:/root/.claude"
    --volume "$WORKSPACE:/src"
  )
  if [[ -f "$MEMORY_FILE" ]]; then
    local absolute_memory_file
    absolute_memory_file="$(cd "$(dirname "$MEMORY_FILE")" && pwd)/$(basename "$MEMORY_FILE")"
    run_options+=(--volume "$absolute_memory_file:/root/.claude/CLAUDE.md:ro")
  elif $MEMORY_FILE_EXPLICIT; then
    echo "Memory file not found: $MEMORY_FILE" >&2
    exit 1
  fi
  if [[ -d "$AGENTS_DIR" ]]; then
    local absolute_agents_dir
    absolute_agents_dir="$(cd "$AGENTS_DIR" && pwd)"
    run_options+=(--volume "$absolute_agents_dir:/root/.claude/agents:ro")
  elif $AGENTS_DIR_EXPLICIT; then
    echo "Agents directory not found: $AGENTS_DIR" >&2
    exit 1
  fi
  if [[ -f "$GH_TOKEN_FILE" ]]; then
    local gh_token_dir
    gh_token_dir="$(cd "$(dirname "$GH_TOKEN_FILE")" && pwd)"
    run_options+=(
      --volume "$gh_token_dir:$CONTAINER_GH_TOKEN_DIR:ro"
      --env "GH_TOKEN_FILE=$CONTAINER_GH_TOKEN_DIR/$(basename "$GH_TOKEN_FILE")"
    )
  elif $GH_TOKEN_FILE_EXPLICIT; then
    echo "GitHub token file not found: $GH_TOKEN_FILE" >&2
    exit 1
  fi
  ensure_image_exists
  echo "Starting a new Claude Code container for $WORKSPACE..."
  if $SHELL_MODE; then
    open_shell_in "$(docker run --detach "${run_options[@]}" "$IMAGE")"
  fi
  exec docker run "${run_options[@]}" "$IMAGE"
}

describe_container() {
  docker inspect --format '{{.Name}} ({{.State.Status}}, created {{.Created}})' "$1" | sed 's|^/||'
}

choose_container() {
  local containers=("$@")
  local index
  echo "Containers for $WORKSPACE:"
  for index in "${!containers[@]}"; do
    echo "  $((index + 1))) $(describe_container "${containers[$index]}")"
  done
  echo "  n) Start a new container"
  local answer
  while true; do
    read -r -p "Choose a container [1]: " answer
    answer="${answer:-1}"
    if [[ "$answer" =~ ^[Nn]$ ]]; then
      CHOSEN_CONTAINER=""
      return
    fi
    if [[ "$answer" =~ ^[0-9]+$ ]] && ((answer >= 1 && answer <= ${#containers[@]})); then
      CHOSEN_CONTAINER="${containers[$((answer - 1))]}"
      return
    fi
    echo "Enter a number from 1 to ${#containers[@]}, or n." >&2
  done
}

resume_container() {
  local container="$1"
  echo "Starting container $(describe_container "$container")"
  if $SHELL_MODE; then
    docker start "$container" >/dev/null
    open_shell_in "$container"
  fi
  exec docker start --attach --interactive "$container"
}

if $REBUILD; then
  offer_rebuild
fi

if $SHELL_MODE; then
  candidate_statuses=(running exited created)
else
  candidate_statuses=(exited created)
fi
candidate_containers=()
while IFS= read -r container; do
  candidate_containers+=("$container")
done < <(containers_with_status "${candidate_statuses[@]}")

if ((${#candidate_containers[@]} > 0)); then
  choose_container "${candidate_containers[@]}"
  if [[ -n "$CHOSEN_CONTAINER" ]]; then
    resume_container "$CHOSEN_CONTAINER"
  fi
fi

start_new_container
