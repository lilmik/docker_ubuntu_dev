#!/bin/bash
set -euo pipefail

install -d -m 0755 /run/sshd

# ---- 首次/按需补齐 /app 内容（不覆盖已有）----
if [ -d /opt/app_base ]; then
  mkdir -p /app
  if [ -z "$(ls -A /app 2>/dev/null)" ]; then
    cp -a /opt/app_base/. /app/
  else
    cp -an /opt/app_base/. /app/ 2>/dev/null || true
  fi
  [ "${APP_CHOWN_DEV:-0}" = "1" ] && chown -R dev:dev /app || true
  rm -rf /opt/app_base || true
fi

# 启动时时间同步（完全静默后台执行）
echo "启动时间同步（后台执行）..."
export NTP_LOG_MODE=none
/usr/local/bin/time-sync set > /dev/null 2>&1 &

service cron start
exec /usr/sbin/sshd -D -e
