#!/usr/bin/env bash
# 启动本地 Web UI（自动打开浏览器）
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 -m webui.server "$@"
