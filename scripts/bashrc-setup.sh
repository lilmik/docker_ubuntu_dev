# 确保与bash.bashrc同步
if [ -f /etc/bash.bashrc ]; then
  # shellcheck disable=SC1091
  . /etc/bash.bashrc
fi