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

# 只设置时区为上海（不进行时间同步）
echo "设置时区为 Asia/Shanghai..."
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
echo "Asia/Shanghai" > /etc/timezone

# 启动 cron 服务
service cron start

# 生成 SSH 主机密钥（如果不存在）
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    ssh-keygen -A
fi

# 启动 SSH 服务并保持前台运行
echo "启动 SSH 服务..."
exec /usr/sbin/sshd -D -e

# # 启动时时间同步（完全静默后台执行）
# echo "启动时间同步（后台执行）..."
# export NTP_LOG_MODE=none
# /usr/local/bin/time-sync set > /dev/null 2>&1 &

# service cron start
# exec /usr/sbin/sshd -D -e
