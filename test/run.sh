#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${LUA:-lua}" "$dir/smoke/props.lua"
