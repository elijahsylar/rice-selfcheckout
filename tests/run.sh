#!/usr/bin/env bash
# Checks that need no desktop session: GRTA mood schedule (Lua), shell
# syntax, the new-tab page's JavaScript, and an optional overlay build.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."

LUA="$(command -v lua || command -v lua5.4 || command -v lua5.3 || true)"
[[ -n "$LUA" ]] || { echo "lua not found (install lua5.4)"; exit 1; }

echo "== GRTA mood schedule"
"$LUA" tests/test_moods.lua | tail -1

echo "== shell syntax"
for f in install.sh overlay/toggle.sh scripts/*; do bash -n "$f" && echo "ok   $f"; done

echo "== new-tab JavaScript parses"
node -e '
const fs = require("fs"), vm = require("vm");
const html = fs.readFileSync("browsers/librewolf/newtab/index.html", "utf8");
const blocks = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m => m[1]);
blocks.forEach((c, i) => new vm.Script(c, { filename: "index.html#script" + i }));
new vm.Script(fs.readFileSync("browsers/librewolf/newtab/config.js", "utf8"));
console.log("ok   " + blocks.length + " inline scripts + config.js");'

if command -v cc >/dev/null && [[ -f /usr/include/X11/Xlib.h ]]; then
  echo "== overlay builds"
  make -s -C overlay crt-overlay && make -s -C overlay clean && echo "ok   overlay/main.c"
else
  echo "== overlay build skipped (needs cc + libx11-dev, libxext-dev, libgl-dev)"
fi
echo "all checks passed"
