# ============================================================
# 基础环境阶段：不干扰系统Python（修复版）
# ============================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
# 确保 bash 启动时加载全局配置
ENV BASH_ENV="/etc/bash.bashrc"
# 明确虚拟环境路径（与系统 Python 隔离）
ENV VIRTUAL_ENV="/opt/venv"

# 1.更新APT并安装基础包
RUN apt update && apt install -y \
    apt-utils apt-file bash-completion \
    tzdata ntpdate cron \
    openssh-server sudo \
    net-tools iputils-ping \
    git curl wget \
    build-essential \
    python3 python3-pip python3-venv python-is-python3 \
    libgl1-mesa-glx libglib2.0-0 \
    libopenblas-base \
    figlet lolcat neofetch btop \
    nano vim \
 && rm -rf /var/lib/apt/lists/* \
 && apt clean

# 2.设置时区（验证）
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \
    dpkg-reconfigure -f noninteractive tzdata && \
    echo "时区设置验证: $(date +%Z)"

# 3.启用bash自动补全
RUN echo "source /etc/bash_completion" >> /etc/bash.bashrc

# 4.初始化SSH环境与配置
RUN ssh-keygen -A && mkdir -p /run/sshd && chmod 0755 /run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# 5.创建 dev 用户（带 sudo 权限）
RUN useradd -m -d /home/dev -s /bin/bash dev && \
    echo "dev:dev" | chpasswd && \
    echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    chown -R dev:dev /home/dev && \
    chmod 755 /home/dev && \
    echo "用户创建验证: $(grep dev /etc/passwd)"



# 6.创建独立虚拟环境（完全隔离系统 Python）
# pip 全局镜像（系统 pip + venv pip 都生效）
RUN printf '%s\n' \
    '[global]' \
    'index-url = https://mirrors.ustc.edu.cn/pypi/web/simple' \
    'trusted-host = mirrors.ustc.edu.cn' \
    'timeout = 30' \
    'retries = 5' \
    > /etc/pip.conf

RUN python3 -m venv $VIRTUAL_ENV && \
    $VIRTUAL_ENV/bin/pip install --no-cache-dir --upgrade pip setuptools wheel && \
    chown -R dev:dev $VIRTUAL_ENV && \
    chmod -R 755 $VIRTUAL_ENV && \
    echo "虚拟环境创建验证: $(ls -ld $VIRTUAL_ENV/bin/python)"

# ============================================================
# 【提前执行】依赖管理：虚拟环境创建后立即安装依赖
# ============================================================

# 7.准备 /app 目录
RUN mkdir -p /app && \
    chown -R dev:dev /app && \
    chmod -R 755 /app && \
    echo "app目录验证: $(ls -ld /app)"

# 8.仅复制依赖文件（同层目录 ./app → 镜像 /app/）
#    需存在下列任一文件：
#    - ./app/requirements-locked.txt
#    - ./app/requirements.txt
COPY --chown=dev:dev ./app/requirements*.txt /app/
COPY --chown=dev:dev ./app/*.py /app/

RUN mkdir -p /opt/app_base && \
    cp -a /app/. /opt/app_base/

# 9.依赖文件校验 + 安装（缺失则中止构建）
RUN set -e; \
    if [ -f "/app/requirements-locked.txt" ]; then \
        echo "[deps] 使用 requirements-locked.txt"; \
        REQ="/app/requirements-locked.txt"; \
    elif [ -f "/app/requirements.txt" ]; then \
        echo "[deps] 使用 requirements.txt"; \
        REQ="/app/requirements.txt"; \
    else \
        echo "[ERROR] 未找到依赖文件：/app/requirements(-locked).txt" >&2; \
        exit 1; \
    fi; \
    "$VIRTUAL_ENV/bin/pip" install --no-cache-dir -r "$REQ" && \
    echo "[deps] 依赖安装完成，已安装包数量: $($VIRTUAL_ENV/bin/pip list | wc -l)"

# ============================================================
# 环境配置：配置python venv环境, 交互式 shell 自动激活 venv（一次）+ 动态(venv)标识
# ============================================================

# 10.重置基线 PATH（不含 venv；补 /usr/games 以便 lolcat）
ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games"

# 11.登录/SSH 场景（/etc/profile.d）：交互式 shell 首次自动激活 + 动态(venv)提示
RUN cat <<'EOF' > /etc/profile.d/zz-auto-venv.sh
# ---- auto-activate venv once for interactive shells & dynamic (venv) ----
case $- in *i*) ;; *) return ;; esac

# 首次进入本会话自动激活（不改全局 PATH）
if [ -z "${_AUTO_VENV_DONE:-}" ] && [ -r /opt/venv/bin/activate ]; then
  unset VIRTUAL_ENV_DISABLE_PROMPT
  # shellcheck disable=SC1091
  . /opt/venv/bin/activate
  export _AUTO_VENV_DONE=1
fi

# 动态 (venv) 标签：激活时加、退出后移除
_venv_ps1_update() {
  local tag_old="${_VENV_PS1_TAG:-}" tag_new=""
  if [ -n "${VIRTUAL_ENV:-}" ]; then tag_new="($(basename "$VIRTUAL_ENV"))"; fi
  # 移除旧标签（仅移除我们加过的前缀）
  if [ -n "$tag_old" ] && [ "${PS1#${tag_old} }" != "$PS1" ]; then
    PS1="${PS1#${tag_old} }"
  fi
  # 添加新标签（如需）
  if [ -n "$tag_new" ] && [ "${PS1#${tag_new} }" = "$PS1" ]; then
    PS1="$tag_new $PS1"
  fi
  export _VENV_PS1_TAG="$tag_new"
}
case "$PROMPT_COMMAND" in
  *_venv_ps1_update*) ;;
  *) PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}_venv_ps1_update" ;;
esac
# ---- end ----
EOF

# 12.非登录交互 bash（docker exec /bin/bash）：注入相同逻辑
RUN cat <<'EOF' >> /etc/bash.bashrc
# ---- auto-activate venv once (interactive non-login bash) & dynamic prompt ----
if [[ $- == *i* ]]; then
  if [[ -z "${_AUTO_VENV_DONE:-}" ]] && [[ -r /opt/venv/bin/activate ]]; then
    unset VIRTUAL_ENV_DISABLE_PROMPT
    # shellcheck disable=SC1091
    . /opt/venv/bin/activate
    export _AUTO_VENV_DONE=1
  fi
  _venv_ps1_update() {
    local tag_old="${_VENV_PS1_TAG:-}" tag_new=""
    if [[ -n "${VIRTUAL_ENV:-}" ]]; then tag_new="($(basename "$VIRTUAL_ENV"))"; fi
    if [[ -n "$tag_old" ]] && [[ "${PS1#${tag_old} }" != "$PS1" ]]; then
      PS1="${PS1#${tag_old} }"
    fi
    if [[ -n "$tag_new" ]] && [[ "${PS1#${tag_new} }" == "$PS1" ]]; then
      PS1="$tag_new $PS1"
    fi
    export _VENV_PS1_TAG="$tag_new"
  }
  case "$PROMPT_COMMAND" in
    *_venv_ps1_update*) ;;
    *) PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}_venv_ps1_update" ;;
  esac
fi
# ---- end ----
EOF

# ============================================================
# 登录信息脚本与 SSH/cron 启动配置
# ============================================================

# 13.登录信息展示脚本（heredoc，稳定）
RUN cat <<'EOF' > /usr/local/bin/show-login-info && chmod +x /usr/local/bin/show-login-info
#!/bin/bash
set -euo pipefail
# 为本脚本补 PATH，确保找到 lolcat（/usr/games）
PATH="$PATH:/usr/games:/usr/local/games"
command_exists() { command -v "$1" >/dev/null 2>&1; }

# 显示主机名艺术字
if command_exists figlet && command_exists lolcat; then
  figlet -f slant "$(hostname)" | lolcat
elif command_exists figlet; then
  figlet -f slant "$(hostname)"
fi

# 显示系统信息
if command_exists neofetch; then
  if command_exists lolcat; then
    neofetch --stdout | lolcat
  else
    neofetch --stdout
  fi
fi

# ---- 彩色标签工具（轮换配色，自动降级无色） ----
USE_COLOR=1
[ -t 1 ] || USE_COLOR=0          # 非终端输出（如重定向）则不着色
[ "${NO_COLOR:-}" = "1" ] && USE_COLOR=0

# 可按喜好调整顺序/颜色
COLORS=(
  "\033[1;34m"  # 蓝
  "\033[1;32m"  # 绿
  "\033[1;35m"  # 品红
  "\033[1;36m"  # 青
  "\033[1;33m"  # 黄
  "\033[1;31m"  # 红
)
RESET="\033[0m"
COLOR_IDX=0

lprint() {
  local label="$1" value="$2" color
  color="${COLORS[$COLOR_IDX]}"
  COLOR_IDX=$(( (COLOR_IDX + 1) % ${#COLORS[@]} ))
  if [ "$USE_COLOR" -eq 1 ]; then
    # %b 让转义序列生效
    printf "%b%s%b %s\n" "$color" "$label" "$RESET" "$value"
  else
    printf "%s %s\n" "$label" "$value"
  fi
}

# ==================== 信息输出 ====================

# 网络与时间信息
lprint "IP地址："     "$(hostname -I | awk '{print $1}')"
lprint "当前时间："   "$(date '+%Y-%m-%d %H:%M:%S')"
lprint "当前时区："   "$(cat /etc/timezone 2>/dev/null || date +%Z)"

# Python / venv 信息
if command_exists python3 || command_exists python; then
  PYV=$(/usr/bin/env python3 -V 2>&1 || /usr/bin/env python -V 2>&1)
  PYBIN=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "未找到")
  if [ -n "${VIRTUAL_ENV:-}" ]; then
    VENV_STATE="已激活"
    VENV_PATH="$VIRTUAL_ENV"
  else
    VENV_STATE="未激活"
    VENV_PATH="/opt/venv（未激活）"
  fi

  lprint "(venv)Python版本："   "$PYV"
  lprint "激活命令："     "source /opt/venv/bin/activate"
  lprint "取消激活："     "deactivate"
fi
EOF

# 13b.登录信息脚本：补充 bashrc，确保补全可用 & 自动显示登录信息
RUN echo "source /etc/bash_completion" >> /etc/bash.bashrc && \
    echo "if [ -t 0 ]; then /usr/local/bin/show-login-info; fi" >> /etc/bash.bashrc && \
    rm -f /etc/update-motd.d/10-help-text /etc/update-motd.d/50-motd-news


# 14.定时任务：每小时同步时间（使用绝对路径，不用 sudo）
RUN cat <<'EOF' > /etc/cron.hourly/ntp-sync && chmod +x /etc/cron.hourly/ntp-sync
#!/bin/bash
set -e
{
  echo "=== 定时任务同步开始: $(date) ==="
  /usr/sbin/ntpdate -v ntp.aliyun.com time1.aliyun.com ntp1.aliyun.com
  echo "=== 定时任务同步结束（状态：$?） ==="
} >> /var/log/ntp-sync.log 2>&1
EOF

# 15.容器启动脚本：启动前同步一次时间 +（按需）补齐/app + 开 cron + 前台 sshd
RUN cat <<'EOF' > /start.sh && chmod +x /start.sh
#!/bin/bash
set -euo pipefail

# 运行期确保 /run/sshd 存在（有些基镜像 /run 为 tmpfs）
install -d -m 0755 /run/sshd

# ---- 首次/按需补齐 /app 内容（不覆盖已有）----
# 说明：/opt/app_base 需在构建期准备好（见下文 Dockerfile 补充）
if [ -d /opt/app_base ]; then
  mkdir -p /app
  if [ -z "$(ls -A /app 2>/dev/null)" ]; then
    # 完全空目录：整包拷入
    cp -a /opt/app_base/. /app/
  else
    # 非空：只补缺文件
    cp -an /opt/app_base/. /app/ 2>/dev/null || true
  fi
  # 可选：把权限交给 dev（注意：bind mount 会改宿主侧权限）
  [ "${APP_CHOWN_DEV:-0}" = "1" ] && chown -R dev:dev /app || true
fi

echo '容器启动时同步时间...'
{
  echo "=== 容器启动时同步开始: $(date) ==="
  /usr/sbin/ntpdate -v ntp.aliyun.com time1.aliyun.com ntp1.aliyun.com || true
  echo "=== 容器启动时同步结束（状态：$?） ==="
} >> /var/log/ntp-sync.log 2>&1

service cron start
# 前台 + 输出到 stderr，便于 docker logs 观察
exec /usr/sbin/sshd -D -e
EOF

# ============================================================
# 强制设定进入容器的工作目录与登录位置
# ============================================================
# 进入容器/SSH 默认在 /app（覆盖所有“交互式”进入方式）
WORKDIR /app

# 登录 shell（SSH、bash -l）自动 cd /app
RUN tee /etc/profile.d/zzz-cd-app.sh >/dev/null <<'EOF'
# 仅交互式 shell 执行，避免影响 scp/脚本
case $- in *i*) ;; *) return ;; esac
if [ -d /app ] && [ -z "${_CD_APP_DONE:-}" ]; then
  cd /app || true
  export _CD_APP_DONE=1
fi
EOF

# 非登录的交互式 bash（docker exec -it ... bash）也自动 cd /app
RUN echo 'if [[ $- == *i* ]] && [[ -z "${_CD_APP_DONE:-}" ]] && [[ -d /app ]]; then cd /app; export _CD_APP_DONE=1; fi' >> /etc/bash.bashrc

# ============================================================
# 容器入口
# ============================================================
EXPOSE 22 80 433 1000 2000 3000 8000 8080
CMD ["/start.sh"]