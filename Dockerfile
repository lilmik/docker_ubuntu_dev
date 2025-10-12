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
    apt-utils apt-file bash-completion tzdata ntpdate chrony cron sudo \
    openssh-server net-tools iputils-ping curl wget chromium-browser \
    build-essential git clang cmake ninja-build pkg-config unzip xz-utils zip ccache \
    python3 python3-pip python3-venv python-is-python3 patchelf \
    libgl1-mesa-glx libglib2.0-0 libopenblas-base libglu1-mesa xvfb libgl1-mesa-dri libgtk-3-dev mesa-utils liblzma-dev \
    figlet lolcat neofetch btop nano vim \
 && rm -rf /var/lib/apt/lists/* \
 && apt clean

# 2.设置时区（验证）
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \
    dpkg-reconfigure -f noninteractive tzdata && \
    echo "时区设置验证: $(date +%Z)"

# 3.启用bash自动补全
RUN echo "source /etc/bash_completion" >> /etc/bash.bashrc
# 修复docker-clean，恢复apt补全
RUN echo "### 仅注释影响补全的配置项 ###" && \
    # 注释单行多配置
    sed -i 's/^Dir::Cache::pkgcache ""; Dir::Cache::srcpkgcache ""/\/\/ &/' /etc/apt/apt.conf.d/docker-clean && \
    # 兼容单行单独配置
    sed -i 's/^Dir::Cache::pkgcache "";/\/\/ &/' /etc/apt/apt.conf.d/docker-clean && \
    sed -i 's/^Dir::Cache::srcpkgcache "";/\/\/ &/' /etc/apt/apt.conf.d/docker-clean

# 4.初始化SSH环境与配置
RUN ssh-keygen -A && mkdir -p /run/sshd && chmod 0755 /run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# 5.创建 dev 用户（带 sudo 权限）,root和dev密码均为 dev
# RUN useradd -m -d /home/dev -s /bin/bash dev && \
#     echo "dev:dev" | chpasswd && \
#     echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
#     chown -R dev:dev /home/dev && \
#     chmod 755 /home/dev && \
#     echo "用户创建验证: $(grep dev /etc/passwd)"
RUN echo "root:dev" | chpasswd && \
    useradd -m -d /home/dev -s /bin/bash dev && \
    echo "dev:dev" | chpasswd && \
    echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    chown -R dev:dev /home/dev && chmod 755 /home/dev

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

# 11.登录/SSH 场景（/etc/profile.d）：修复bash语法错误
RUN cat <<'EOF' > /etc/profile.d/zz-auto-venv.sh
# ---- 修复bash语法错误的自动venv配置 ----
case $- in *i*) ;; *) return ;; esac

if [ -z "${_AUTO_VENV_DONE:-}" ] && [ -r /opt/venv/bin/activate ]; then
  unset VIRTUAL_ENV_DISABLE_PROMPT
  # shellcheck disable=SC1091
  . /opt/venv/bin/activate
  export _AUTO_VENV_DONE=1
fi

if ! command -v _venv_ps1_update &> /dev/null; then
  _venv_ps1_update() {
    local tag_new=""
    if [ -n "${VIRTUAL_ENV:-}" ]; then 
      tag_new="($(basename "$VIRTUAL_ENV"))"
    fi
    
    # 使用更兼容的语法移除标签
    if [ -n "${_VENV_PS1_TAG:-}" ] && [ "${PS1#${_VENV_PS1_TAG} }" != "$PS1" ]; then
      PS1="${PS1#${_VENV_PS1_TAG} }"
    else
      # 修复正则表达式语法，使用变量存储模式
      local venv_pattern='^([^)]+)\) '
      if [[ "$PS1" =~ $venv_pattern ]]; then
        PS1="${PS1#*) }"
      fi
    fi
    
    if [ -n "$tag_new" ] && [ "${PS1#${tag_new} }" = "$PS1" ]; then
      PS1="$tag_new $PS1"
    fi
    
    export _VENV_PS1_TAG="$tag_new"
  }
fi

if [[ ";${PROMPT_COMMAND};" != *";_venv_ps1_update;"* ]]; then
  PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}_venv_ps1_update"
fi
# ---- end ----
EOF

# 12.非登录交互 bash 配置（包括 docker exec bash）
RUN cat <<'EOF' >> /etc/bash.bashrc
# ---- 修复bash语法错误的非登录bash配置 ----
if [[ $- == *i* ]]; then
  if [ -z "${_AUTO_VENV_DONE:-}" ] && [ -d /etc/profile.d ]; then
    for profile in /etc/profile.d/*.sh; do
      if [ -r "$profile" ] && [[ "$profile" == *"zz-auto-venv.sh"* ]]; then
        # shellcheck disable=SC1090
        . "$profile"
      fi
    done
  fi

  if ! command -v _venv_ps1_update &> /dev/null; then
    _venv_ps1_update() {
      local tag_new=""
      if [[ -n "${VIRTUAL_ENV:-}" ]]; then 
        tag_new="($(basename "$VIRTUAL_ENV"))"
      fi
      
      # 使用更兼容的语法移除标签
      if [[ -n "${_VENV_PS1_TAG:-}" ]] && [[ "${PS1#${_VENV_PS1_TAG} }" != "$PS1" ]]; then
        PS1="${PS1#${_VENV_PS1_TAG} }"
      else
        # 修复正则表达式语法，使用变量存储模式
        local venv_pattern='^([^)]+)\) '
        if [[ "$PS1" =~ $venv_pattern ]]; then
          PS1="${PS1#*) }"
        fi
      fi
      
      if [[ -n "$tag_new" ]] && [[ "${PS1#${tag_new} }" == "$PS1" ]]; then
        PS1="$tag_new $PS1"
      fi
      
      export _VENV_PS1_TAG="$tag_new"
    }
  fi

  if [[ ";${PROMPT_COMMAND};" != *";_venv_ps1_update;"* ]]; then
    PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}_venv_ps1_update"
  fi
fi
# ---- end ----
EOF

# 12b.额外处理纯bash交互模式（docker exec -it <container> /bin/bash）
RUN cat <<'EOF' > /etc/bashrc
# 确保与bash.bashrc同步
if [ -f /etc/bash.bashrc ]; then
  # shellcheck disable=SC1091
  . /etc/bash.bashrc
fi
EOF

# ============================================================
# 下载 Flutter SDK 并预缓存
# ============================================================
# 13.下载 Flutter SDK 并预缓存
# 使用绝对路径，避免 $FLUTTER_HOME 展开问题
RUN mkdir -p /opt/flutter \
    && git clone https://github.com/flutter/flutter.git /opt/flutter -b stable --depth 1 \
    && chown -R dev:dev /opt/flutter \
    && chmod -R 755 /opt/flutter \
    && chmod +x /opt/flutter/bin/flutter

# 写入 bashrc，让 root 和 dev 用户登录时直接可用
RUN echo "export FLUTTER_HOME=/opt/flutter" >> /root/.bashrc \
    && echo "export PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:\$PATH" >> /root/.bashrc \
    && echo "export CHROME_EXECUTABLE=/usr/bin/chromium-browser" >> /root/.bashrc \
    && echo "export FLUTTER_HOME=/opt/flutter" >> /home/dev/.bashrc \
    && echo "export PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:\$PATH" >> /home/dev/.bashrc \
    && echo "export CHROME_EXECUTABLE=/usr/bin/chromium-browser" >> /home/dev/.bashrc

# 以 dev 用户执行最小化预缓存，避免第一次运行 Flutter 时下载过慢
USER dev
RUN /opt/flutter/bin/flutter --version \
    && /opt/flutter/bin/flutter config --enable-linux-desktop \
    && /opt/flutter/bin/flutter config --enable-web \
    && /opt/flutter/bin/flutter precache --linux --web \
    && /opt/flutter/bin/flutter --disable-analytics \
    && git config --global --add safe.directory /opt/flutter

# 切回 root 用户，确保 root 也可用 Flutter
USER root
RUN git config --global --add safe.directory /opt/flutter

# ============================================================
# 登录信息脚本与 SSH/cron 启动配置
# ============================================================

# 14.登录信息展示脚本（heredoc，稳定）
# 下载ansi-shadow字体
# 下载 ANSI Shadow 字体到系统目录（统一命名为 ansi-shadow.flf）
RUN set -eux; \
  mkdir -p /usr/share/figlet; \
  curl -fsSL "https://cdn.jsdelivr.net/gh/patorjk/figlet.js/fonts/ANSI%20Shadow.flf" \
    -o "/usr/share/figlet/ansi-shadow.flf"; \
  # 兼容性：顺手做一个带空格的大写别名（可选）
  ln -sf "/usr/share/figlet/ansi-shadow.flf" "/usr/share/figlet/ANSI Shadow.flf"; \
  # 校验非空
  [ -s "/usr/share/figlet/ansi-shadow.flf" ]

RUN cat <<'EOF' > /usr/local/bin/show-login-info && chmod +x /usr/local/bin/show-login-info
#!/bin/bash
set -euo pipefail
# 为本脚本补 PATH，确保找到 lolcat（/usr/games）
PATH="$PATH:/usr/games:/usr/local/games"
command_exists() { command -v "$1" >/dev/null 2>&1; }


# 显示主机名艺术字：ANSI Shadow（已预装到 /usr/share/figlet/ansi-shadow.flf）
# 统一用 UTF-8，防止块字符乱码
export LANG="${LANG:-C.UTF-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"

if command_exists figlet; then
  figlet -d /usr/share/figlet -f ansi-shadow -w 500 -- "$(hostname)" \
    | { command -v lolcat >/dev/null && lolcat || cat; }
fi

# 第一行加粗，仍然走 lolcat 管道
printf "\033[1m%s\033[0m\n" "Welcome! This environment is ready for coding." \
  | { command -v lolcat >/dev/null && lolcat || cat; }

cat <<'EOT' | { command -v lolcat >/dev/null && lolcat || cat; }
• Python & virtualenv are set up.
• Flutter/Dart are preinstalled.
• Your workspace lives in /app.
Have fun and build something awesome!

EOT

# 显示系统信息
# if command_exists neofetch; then
#   if command_exists lolcat; then
#     neofetch --stdout | lolcat
#   else
#     neofetch --stdout
#   fi
# fi
# ====== 优雅着色的 neofetch（标题横幅统一、标签彩色、值默认色） ======
if command_exists neofetch; then
  PATH="$PATH:/usr/games:/usr/local/games"  # 让 lolcat 能被找到
  BANNER_WIDTH="${BANNER_WIDTH:-80}"        # 统一横幅宽度（可改）

  # 工具：整行/片段交给 lolcat；无 lolcat 时原样输出
  _emit_lolcat_line()  { if command -v lolcat >/dev/null; then printf "%b\n" "$1" | lolcat; else printf "%b\n" "$1"; fi; }
  _emit_lolcat_piece() { if command -v lolcat >/dev/null; then printf "%b"    "$1" | lolcat; else printf "%b"    "$1"; fi; }

  # 生成“==== title ====”横幅（粗体由调用处包裹）
  _make_banner() {
    local title="$1"
    local inner=" ${title} "
    local len=${#inner}
    local pad=$(( BANNER_WIDTH - len ))
    [ $pad -lt 0 ] && pad=0
    local left=$(( pad / 2 ))
    local right=$(( pad - left ))
    printf "%*s%s%*s" "$left" "" "$inner" "$right" "" | tr ' ' '='
  }

  ( set +o pipefail 2>/dev/null || true
    header_done=0
    while IFS= read -r line; do
      # 1) 第一次遇到“无冒号且非空”的行，当作标题行，用横幅替换（跳过后面一行分割线）
      if [ $header_done -eq 0 ] && [ -n "$line" ] && [[ "$line" != *:* ]]; then
        banner="$(_make_banner "$line")"
        _emit_lolcat_line "\033[1m${banner}\033[0m"
        header_done=1
        # 读掉下一行（通常是分割线），不输出
        IFS= read -r _discard || true
        continue
      fi

      # 2) 常规行：有冒号 → “标签: ”粗体+彩色，值用默认色；无冒号 → 整行粗体+彩色
      if [[ "$line" == *:* ]]; then
        label="${line%%:*}"
        value="${line#*:}"
        _emit_lolcat_piece "\033[1m${label}:\033[0m"
        printf " %s\n" "${value# }"
      else
        _emit_lolcat_line "\033[1m${line}\033[0m"
      fi
    done < <(neofetch --stdout)
  )
fi
# ====== /neofetch ======

# ===== Strict-ish but tolerant =====
set -o pipefail

# ==================== 颜色与通用函数 ====================
COLOR_MODE="${COLOR_MODE:-auto}"   # auto|256|16（仅在不用 lolcat 时生效）
USE_COLOR="${USE_COLOR:-1}"
COLOR_IDX=0
RESET="\033[0m"
BOLD="\033[1m"

command_exists() { command -v "$1" >/dev/null 2>&1; }

supports_256() { tput colors 2>/dev/null | awk '{exit !($1>=256)}'; }

# lolcat 优先：有就用，无则回退到普通配色
USE_LOLCAT="${USE_LOLCAT:-1}"
LOLCAT_OPTS="${LOLCAT_OPTS:-}"
use_lolcat=0
if [ "$USE_LOLCAT" -eq 1 ] && command_exists lolcat; then
  use_lolcat=1
fi

# 回退配色（仅在不用 lolcat 时用到）
declare -a COLORS
if { [ "$COLOR_MODE" = "256" ] || { [ "$COLOR_MODE" = "auto" ] && supports_256; }; }; then
  COLORS=(
    "\033[38;5;196m" "\033[38;5;202m" "\033[38;5;208m" "\033[38;5;214m"
    "\033[38;5;220m" "\033[38;5;154m" "\033[38;5;082m" "\033[38;5;046m"
    "\033[38;5;051m" "\033[38;5;045m" "\033[38;5;039m" "\033[38;5;033m"
    "\033[38;5;027m" "\033[38;5;129m" "\033[38;5;135m" "\033[38;5;201m"
  )
else
  COLORS=(
    "\033[31m" "\033[33m" "\033[32m" "\033[36m"
    "\033[34m" "\033[35m" "\033[91m" "\033[93m"
    "\033[92m" "\033[96m" "\033[94m" "\033[95m"
  )
fi

# （可选）随机打乱一次颜色顺序，降低“重复感”
if [ "${SHUFFLE_COLORS:-0}" -eq 1 ]; then
  for ((i=${#COLORS[@]}-1; i>0; i--)); do
    j=$(( RANDOM % (i+1) ))
    tmp=${COLORS[i]}
    COLORS[i]=${COLORS[j]}
    COLORS[j]=$tmp
  done
fi

# 安全设置 locale：优先 zh_CN.UTF-8，不存在就用 C.UTF-8（避免警告）
set_locale_safely() {
  local has_zhcn=0
  if command_exists locale; then
    if locale -a 2>/dev/null | grep -qi '^zh_CN\.utf-8$'; then
      has_zhcn=1
    fi
  fi
  if [ "$has_zhcn" -eq 1 ]; then
    export LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8 LC_CTYPE=zh_CN.UTF-8 LANGUAGE=zh_CN:zh
  else
    export LANG=C.UTF-8 LC_ALL=C.UTF-8 LC_CTYPE=C.UTF-8 LANGUAGE=C
  fi
}
set_locale_safely

# —— 统一输出工具：仅在需要时用 lolcat 上色 —— #
_emit_lolcat_line() {
  # 支持 \033[...] 转义并整行上色
  printf "%b\n" "$1" | lolcat $LOLCAT_OPTS
}

_emit_lolcat_piece() {
  # 支持 \033[...] 转义，且不换行（用于“标签+冒号”片段）
  printf "%b" "$1" | lolcat $LOLCAT_OPTS
}

# 带样式的键值打印：
# 需求：冒号及其前面的“标签”= 粗体 + 彩色；冒号之后的“值”= 默认色（不加色）
lprint() {
  local label="$1"
  local value="${2:-}"
  [ -z "$label" ] && { printf "\n"; return; }

  if [ $use_lolcat -eq 1 ]; then
    # 标签（含冒号）粗体并上色；值回到终端默认色
    _emit_lolcat_piece "${BOLD}${label}${RESET}"
    printf " %s\n" "$value"
  else
    local color="${COLORS[$COLOR_IDX]}"
    COLOR_IDX=$(( (COLOR_IDX + 1) % ${#COLORS[@]} ))
    printf "%b%b%s%b %s\n" "$color" "$BOLD" "$label" "$RESET" "$value"
  fi
}

# 彩色横幅（东亚宽度对齐，默认 80 列）
# 需求：整行加粗，并交给 lolcat 上色
print_banner() {
  local title="$1"
  local total="${2:-80}"

  local line
  if command_exists python3; then
    line="$(python3 - "$title" "$total" <<'PYEOF'
import sys, unicodedata
title=sys.argv[1]; total=int(sys.argv[2])
def w(s): return sum(2 if unicodedata.east_asian_width(c) in ('F','W') else 1 for c in s)
inner=f' {title} '; rem=max(total - w(inner), 0); left, right = divmod(rem, 2)
print('='*left + inner + '='*(left+right))
PYEOF
)"
  else
    line="==================== ${title} ===================="
  fi

  if [ $use_lolcat -eq 1 ]; then
    # 注意：把粗体控制码一起传给 _emit_lolcat_line（它用 %b 输出）
    _emit_lolcat_line "${BOLD}${line}${RESET}"
  else
    local color="${COLORS[$COLOR_IDX]}"
    COLOR_IDX=$(( (COLOR_IDX + 1) % ${#COLORS[@]} ))
    printf "%b%b%s%b\n" "$color" "$BOLD" "$line" "$RESET"
  fi
}

# ==================== 信息输出 ====================

# —— 系统网络与时间 —— 
print_banner "系统网络与时间" 80

# IP：优先 ip 命令；无则 hostname -I；最后 ifconfig（尽量避免）
get_ip() {
  if command_exists ip; then
    ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127\.' | head -n1
  elif command_exists hostname; then
    hostname -I 2>/dev/null | awk '{print $1}'
  elif command_exists ifconfig; then
    ifconfig | grep -oE 'inet (addr:)?([0-9]+\.){3}[0-9]+' | awk '{print $2}' | grep -v '^127\.' | head -n1
  fi
}
IP_ADDR="$(get_ip)"
lprint "IP地址："     "${IP_ADDR:-未知}"
lprint "当前时间："   "$(date '+%Y-%m-%d %H:%M:%S')"
# 时区：/etc/timezone（Debian/Ubuntu），或 timedatectl，兜底“未知”
TZ_STR="$(cat /etc/timezone 2>/dev/null || timedatectl show -p Timezone --value 2>/dev/null || echo "未知")"
lprint "当前时区："   "$TZ_STR"
lprint ""

# —— Python / venv 信息 —— 
print_banner "Python 环境信息" 80

if command_exists python3 || command_exists python; then
  if command_exists python3; then
    PYV="$(python3 -V 2>&1)"
    PYBIN="$(command -v python3)"
  else
    PYV="$(python -V 2>&1)"
    PYBIN="$(command -v python)"
  fi

  if [ -n "${VIRTUAL_ENV:-}" ]; then
    VENV_STATE="已激活"
    VENV_PATH="$VIRTUAL_ENV"
  else
    VENV_STATE="未激活"
    VENV_PATH="/opt/venv（未激活）"
  fi

  lprint "Python版本："   "$PYV"
  lprint "Python路径："   "$PYBIN"
  lprint "虚拟环境状态：" "$VENV_STATE"
  lprint "激活命令："     "source /opt/venv/bin/activate"
  lprint "取消激活："     "deactivate"
  lprint "删除虚拟环境：" "rm -rf /opt/venv/"
  lprint "新建虚拟环境：" "python -m venv /opt/new_venv/ && source /opt/new_venv/bin/activate"
else
  lprint "Python环境："   "未安装"
fi
lprint ""

# —— Flutter / Dart 信息（健壮版解析） —— 
print_banner "Flutter / Dart 信息" 80

FLUTTER_PATHS=(
  "/opt/flutter/bin/flutter"
  "$HOME/flutter/bin/flutter"
  "/usr/local/flutter/bin/flutter"
)
export PATH="$PATH:/opt/flutter/bin"

FLUTTER_FOUND=0
FLUTTER_CMD=""

for path in "${FLUTTER_PATHS[@]}"; do
  [ -x "$path" ] && FLUTTER_CMD="$path" && FLUTTER_FOUND=1 && break
done
if [ $FLUTTER_FOUND -eq 0 ] && command_exists flutter; then
  FLUTTER_CMD="$(command -v flutter)"
  FLUTTER_FOUND=1
fi

if [ $FLUTTER_FOUND -eq 1 ]; then
  export PATH="$(dirname "$FLUTTER_CMD"):$PATH"

  # Flutter 版本：匹配 "Flutter 3.24.3" 之类
  FLUTTER_V="$(flutter --version 2>&1 | sed -n 's/^Flutter \([0-9.]\+\).*/\1/p' | head -n1)"
  [ -z "$FLUTTER_V" ] && FLUTTER_V="$(flutter --version 2>&1 | awk '/^Flutter /{print $2; exit}')"

  # Dart 路径：若系统无 dart，则从 Flutter 缓存推断
  DART_CMD=""
  if command_exists dart; then
    DART_CMD="$(command -v dart)"
  else
    _fc="$FLUTTER_CMD"
    if command_exists readlink; then
      _resolved="$(readlink -f "$_fc" 2>/dev/null || echo "$_fc")"
    else
      _resolved="$_fc"
    fi
    FLUTTER_HOME="$(cd "$(dirname "$_resolved")/.." 2>/dev/null && pwd -P)"
    CANDIDATE_DART="$FLUTTER_HOME/bin/cache/dart-sdk/bin/dart"
    [ -x "$CANDIDATE_DART" ] && DART_CMD="$CANDIDATE_DART"
  fi

  # Dart 版本：优先 dart --version（常走 stderr）；兜底 flutter --version 抓取
  if [ -n "$DART_CMD" ]; then
    DART_V="$("$DART_CMD" --version 2>&1 | sed -n 's/^Dart SDK version: \([0-9.]\+\).*/\1/p' | head -n1)"
  fi
  [ -z "$DART_V" ] && DART_V="$(flutter --version 2>&1 | sed -n 's/.*Dart \([0-9.]\+\).*/\1/p' | head -n1)"

  lprint "Flutter版本："  "${FLUTTER_V:-未知}"
  lprint "Flutter路径："  "$FLUTTER_CMD"
  lprint "Dart版本："     "${DART_V:-未知}"
  lprint "Dart路径："     "${DART_CMD:-未发现（由 Flutter 管理）}"
  lprint "Flutter命令："  "flutter doctor、flutter build 等"
else
  lprint "Flutter环境："  "未安装（请确认 /opt/flutter 或 PATH）"
  lprint "Dart环境："     "通常由 Flutter 内置（未单独安装）"
fi
EOF

# 15.登录信息脚本：补充 bashrc，确保补全可用 & 自动显示登录信息
# RUN echo "source /etc/bash_completion" >> /etc/bash.bashrc && \
#     echo "if [ -t 0 ]; then /usr/local/bin/show-login-info; fi" >> /etc/bash.bashrc && \
#     rm -f /etc/update-motd.d/10-help-text /etc/update-motd.d/50-motd-news
RUN echo "source /etc/bash_completion" >> /etc/bash.bashrc \
 && echo "if [ -t 0 ]; then /usr/local/bin/show-login-info; fi" >> /etc/bash.bashrc \
 && touch /root/.hushlogin /home/dev/.hushlogin \
 && chown dev:dev /home/dev/.hushlogin \
 && rm -f /etc/update-motd.d/10-help-text /etc/update-motd.d/50-motd-news \
 && chmod -x /etc/update-motd.d/* || true \
 && rm -f /run/motd.dynamic || true \
 && : > /etc/motd
# 彻底禁止 PAM 的 MOTD（SSH 与本地登录都不再生成/显示）
RUN set -eux; \
    sed -i.bak -E 's/^(\s*session\s+optional\s+pam_motd\.so.*)$/# \1/' /etc/pam.d/sshd; \
    sed -i.bak -E 's/^(\s*session\s+optional\s+pam_motd\.so.*)$/# \1/' /etc/pam.d/login; \
    mkdir -p /etc/ssh/sshd_config.d; \
    printf "PrintMotd no\nPrintLastLog no\n" > /etc/ssh/sshd_config.d/99-no-motd.conf


# 16.定时任务：每小时同步时间（使用绝对路径，不用 sudo）
RUN cat <<'EOF' > /etc/cron.hourly/ntp-sync && chmod +x /etc/cron.hourly/ntp-sync
#!/bin/bash
set -e
{
  echo "=== 定时任务同步开始: $(date) ==="
  /usr/sbin/ntpdate -v ntp.aliyun.com time1.aliyun.com ntp1.aliyun.com
  echo "=== 定时任务同步结束（状态：$?） ==="
} >> /var/log/ntp-sync.log 2>&1
EOF

# 17.容器启动脚本：启动前同步一次时间 +（按需）补齐/app + 开 cron + 前台 sshd
RUN cat <<'EOF' > /start.sh && chmod +x /start.sh
#!/bin/bash
set -euo pipefail

# 运行期确保 /run/sshd 存在（有些基镜像 /run 为 tmpfs）
install -d -m 0755 /run/sshd

# ---- 首次/按需补齐 /app 内容（不覆盖已有）→ 完成后删除源目录 ----
if [ -d /opt/app_base ]; then
  mkdir -p /app

  if [ -z "$(ls -A /app 2>/dev/null)" ]; then
    # 完全空目录：整包拷入
    cp -a /opt/app_base/. /app/
  else
    # 非空：只补缺文件（不覆盖已有）
    cp -an /opt/app_base/. /app/ 2>/dev/null || true
  fi

  # 可选：把权限交给 dev（注意 bind mount 会改宿主侧权限）
  [ "${APP_CHOWN_DEV:-0}" = "1" ] && chown -R dev:dev /app || true

  # 补齐后删除源目录（仅影响容器可写层，不会减小镜像大小）
  rm -rf /opt/app_base || true
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