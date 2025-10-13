# /etc/profile.d/99-show-login-info.sh
# 仅交互式 shell 执行；避免在非交互/CI里输出
case "$-" in *i*) ;; *) return ;; esac

# 只展示一次（同一层级shell不重复；新开一个终端会重新展示）
if [ -z "${_LOGIN_INFO_SHOWN:-}" ] && [ -x /usr/local/bin/show-login-info ]; then
  /usr/local/bin/show-login-info
  export _LOGIN_INFO_SHOWN=1
fi
