#!/usr/bin/env bash
# setup_library.sh - 初始化空目标岗位库 CSV（按 schema 模板）
# 用法: bash scripts/setup_library.sh
# 环境变量: LIB_CSV (默认 ./target_library.csv)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_CSV="${LIB_CSV:-./target_library.csv}"
TEMPLATE="$SCRIPT_DIR/../assets/target_library_template.csv"

if [ -f "$LIB_CSV" ]; then
  echo "[skip] 已存在: $LIB_CSV"
  exit 0
fi
if [ ! -f "$TEMPLATE" ]; then
  echo "FAIL_LOUD: 模板不存在: $TEMPLATE" >&2
  exit 1
fi
cp "$TEMPLATE" "$LIB_CSV"
echo "[ok] 已生成空岗位库: $LIB_CSV"
