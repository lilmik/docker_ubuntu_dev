# 仅交互式登录 shell 执行（避免影响 scp/脚本等非交互场景）
case $- in *i*) ;; *) return 0 2>/dev/null || : ;; esac

# 在登录 shell 中自动切到 /app（同一会话只执行一次）
if [ -d /app ] && [ -z "${_CD_APP_DONE:-}" ]; then
  cd /app || true
  export _CD_APP_DONE=1
fi
