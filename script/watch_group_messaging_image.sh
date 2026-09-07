#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="${CHATWOOT_IMAGE:-chatwoot-preview:group-messaging-v4.17.1}"
DOCKERFILE="${CHATWOOT_DOCKERFILE:-docker/Dockerfile}"
INTERVAL="${CHATWOOT_WATCH_INTERVAL:-2}"
BUILD_PROGRESS="${DOCKER_BUILDKIT_PROGRESS:-plain}"
ONCE=false

usage() {
  cat <<'EOF'
Usage:
  script/watch_group_messaging_image.sh [options]

Options:
  --once              Build once and exit.
  --interval SECONDS  Poll interval (default: 2).
  --image IMAGE       Docker image tag.
  --dockerfile FILE   Dockerfile path relative to the repository root.
  -h, --help          Show this help.
EOF
}

while (($# > 0)); do
  case "$1" in
    --once)
      ONCE=true
      shift
      ;;
    --interval)
      INTERVAL="${2:?missing value for --interval}"
      shift 2
      ;;
    --image)
      IMAGE_NAME="${2:?missing value for --image}"
      shift 2
      ;;
    --dockerfile)
      DOCKERFILE="${2:?missing value for --dockerfile}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

cd "$ROOT_DIR"

WATCH_PATHS=(
  app config db/migrate db/seeds.rb docker lib spec
  Gemfile Gemfile.lock package.json pnpm-lock.yaml
  vite.config.ts vite.lib.config.ts vite.sdk.analyze.config.mts vite.shared.ts
  VERSION_CW
)

if command -v shasum >/dev/null 2>&1; then
  HASH_COMMAND=(shasum -a 256)
elif command -v sha256sum >/dev/null 2>&1; then
  HASH_COMMAND=(sha256sum)
else
  echo "Neither shasum nor sha256sum is installed." >&2
  exit 1
fi

snapshot() {
  local path file metadata
  {
    for path in "${WATCH_PATHS[@]}"; do
      if [[ -f "$path" ]]; then
        printf '%s\n' "$path"
      elif [[ -d "$path" ]]; then
        find "$path" \
          -type d \( -name node_modules -o -name tmp -o -name log -o -name storage \) -prune -o \
          -type f -print
      fi
    done
  } | sort -u | while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    if stat -f '%m:%z' "$file" >/dev/null 2>&1; then
      metadata="$(stat -f '%m:%z' "$file")"
    else
      metadata="$(stat -c '%Y:%s' "$file")"
    fi
    printf '%s:%s\n' "$file" "$metadata"
  done | "${HASH_COMMAND[@]}" | awk '{print $1}'
}

build_image() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Building $IMAGE_NAME"
  local build_command=(docker build)
  if docker buildx version >/dev/null 2>&1; then
    build_command=(docker buildx build --load --progress="$BUILD_PROGRESS")
  fi
  if "${build_command[@]}" -f "$DOCKERFILE" -t "$IMAGE_NAME" .; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Image ready: $IMAGE_NAME"
    return 0
  fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Image build failed; watching continues." >&2
  return 1
}

if [[ "$ONCE" == true ]]; then
  build_image
  exit $?
fi

echo "Watching Chatwoot backend/frontend changes under $ROOT_DIR"
echo "Image: $IMAGE_NAME; interval: ${INTERVAL}s"
echo "Press Ctrl-C to stop."

last_snapshot=""
while true; do
  current_snapshot="$(snapshot)"
  if [[ "$current_snapshot" != "$last_snapshot" ]]; then
    [[ -z "$last_snapshot" ]] || echo "[$(date '+%Y-%m-%d %H:%M:%S')] Change detected"
    build_image || true
    last_snapshot="$current_snapshot"
  fi
  sleep "$INTERVAL"
done
