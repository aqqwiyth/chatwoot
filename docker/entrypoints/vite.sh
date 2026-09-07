#!/bin/sh
set -x

rm -rf /app/tmp/pids/server.pid
rm -rf /app/tmp/cache/*

if [ ! -x /app/node_modules/.bin/vite ]; then
  echo "Vite dependencies are missing; installing from the lockfile."
  pnpm install --offline || pnpm install
else
  echo "Vite dependencies already present; skipping pnpm install."
fi

echo "Ready to run Vite development server."

exec "$@"
