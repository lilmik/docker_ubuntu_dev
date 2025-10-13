# ============================================================
# 基础环境阶段
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

# 3.创建 dev 用户（带 sudo 权限）,root和dev密码均为 dev
RUN echo "root:dev" | chpasswd && \
    useradd -m -d /home/dev -s /bin/bash dev && \
    echo "dev:dev" | chpasswd && \
    # 用更安全的sudoers.d替代直接改/etc/sudoers
    echo "dev ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/dev && \
    chown root:root /etc/sudoers.d/dev && \
    chmod 0440 /etc/sudoers.d/dev && \
    # 兜底修复sudo权限（防止被后续操作破坏）
    chown root:root /usr/bin/sudo && \
    chmod 4755 /usr/bin/sudo && \
    # 家目录权限配置
    chown -R dev:dev /home/dev && \
    chmod 755 /home/dev && \
    echo "用户创建验证: $(grep dev /etc/passwd)"

# 4.创建独立虚拟环境（完全隔离系统 Python）
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
# python包安装：虚拟环境创建后立即安装
# ============================================================

# 5.准备 /app 目录
RUN mkdir -p /app && \
    chown -R dev:dev /app && \
    chmod -R 755 /app && \
    echo "app目录验证: $(ls -ld /app)"

# 6.仅复制依赖文件（同层目录 ./app → 镜像 /app/）
#    需存在下列任一文件：
#    - ./app/requirements-locked.txt
#    - ./app/requirements.txt
COPY --chown=dev:dev ./app/requirements*.txt /app/
COPY --chown=dev:dev ./app/*.py /app/

RUN mkdir -p /opt/app_base && \
    cp -a /app/. /opt/app_base/

# 7.依赖文件校验 + 安装（缺失则中止构建）
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
# 下载 Flutter SDK 并预缓存
# ============================================================
# 8.下载 Flutter SDK 并预缓存
# 使用绝对路径，避免 $FLUTTER_HOME 展开问题
RUN mkdir -p /opt/flutter \
    && git clone https://github.com/flutter/flutter.git /opt/flutter -b stable --depth 1 \
    && chown -R dev:dev /opt/flutter \
    && chmod -R 755 /opt/flutter \
    && chmod +x /opt/flutter/bin/flutter

# 9.写入 bashrc，让 root 和 dev 用户登录时直接可用
RUN echo "export FLUTTER_HOME=/opt/flutter" >> /root/.bashrc \
    && echo "export PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:\$PATH" >> /root/.bashrc \
    && echo "export CHROME_EXECUTABLE=/usr/bin/chromium-browser" >> /root/.bashrc \
    && echo "export FLUTTER_HOME=/opt/flutter" >> /home/dev/.bashrc \
    && echo "export PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:\$PATH" >> /home/dev/.bashrc \
    && echo "export CHROME_EXECUTABLE=/usr/bin/chromium-browser" >> /home/dev/.bashrc

# 10.以 dev 用户执行最小化预缓存，避免第一次运行 Flutter 时下载过慢
USER dev
RUN /opt/flutter/bin/flutter --version \
    && /opt/flutter/bin/flutter config --enable-linux-desktop \
    && /opt/flutter/bin/flutter config --enable-web \
    && /opt/flutter/bin/flutter precache --linux --web \
    && /opt/flutter/bin/flutter --disable-analytics \
    && git config --global --add safe.directory /opt/flutter

# 11.切回 root 用户，确保 root 也可用 Flutter
USER root
RUN git config --global --add safe.directory /opt/flutter


# ============================================================
# 启用bash自动补全、SSH环境配置
# ============================================================

# 12.启用bash自动补全
RUN echo "source /etc/bash_completion" >> /etc/bash.bashrc
# 修复docker-clean，恢复apt补全
RUN echo "### 仅注释影响补全的配置项 ###" && \
    # 注释单行多配置
    sed -i 's/^Dir::Cache::pkgcache ""; Dir::Cache::srcpkgcache ""/\/\/ &/' /etc/apt/apt.conf.d/docker-clean && \
    # 兼容单行单独配置
    sed -i 's/^Dir::Cache::pkgcache "";/\/\/ &/' /etc/apt/apt.conf.d/docker-clean && \
    sed -i 's/^Dir::Cache::srcpkgcache "";/\/\/ &/' /etc/apt/apt.conf.d/docker-clean

# 13.初始化SSH环境与配置
RUN ssh-keygen -A && mkdir -p /run/sshd && chmod 0755 /run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config


# ============================================================
# 环境配置：配置自动激活python venv环境, 交互式 shell 自动激活 venv（一次）+ 动态(venv)标识
# ============================================================

# 复制脚本文件到容器中
COPY scripts/auto-venv-profile.sh /etc/profile.d/zz-auto-venv.sh
COPY scripts/bash-bashrc-append.sh /tmp/bash-bashrc-append.sh
COPY scripts/bashrc-setup.sh /etc/bashrc
COPY scripts/fix-deactivate.sh /usr/local/bin/fix-deactivate
COPY scripts/test-deactivate.sh /usr/local/bin/test-deactivate
COPY scripts/venv-diag.sh /usr/local/bin/venv-diag

# 设置执行权限
RUN chmod +x /etc/profile.d/zz-auto-venv.sh && \
    chmod +x /usr/local/bin/fix-deactivate && \
    chmod +x /usr/local/bin/test-deactivate && \
    chmod +x /usr/local/bin/venv-diag

# 将bash配置追加到现有文件
RUN cat /tmp/bash-bashrc-append.sh >> /etc/bash.bashrc && \
    rm -f /tmp/bash-bashrc-append.sh

# ============================================================
# 登录信息脚本与 SSH/cron 启动配置
# ============================================================

# 14.预置 figlet 字体（无需联网）
COPY --chmod=0644 assets/figlet/ansi-shadow.flf /usr/share/figlet/ansi-shadow.flf
# 兼容别名 + 健康检查（无网络）
RUN set -eux; \
    # 兼容“ANSI Shadow.flf”带空格的老名字
    ln -sf "/usr/share/figlet/ansi-shadow.flf" "/usr/share/figlet/ANSI Shadow.flf"; \
    # 去 CRLF（防止仓库里被 Windows 换行污染）
    sed -i 's/\r$//' /usr/share/figlet/ansi-shadow.flf || true; \
    # 基本健康检查：非空且是 figlet flf2a 格式
    test -s /usr/share/figlet/ansi-shadow.flf; \
    head -c 32 /usr/share/figlet/ansi-shadow.flf | grep -q 'flf2a' ; \
    :

# 15.登录信息展示脚本（支持 登录/非登录 所有交互式Shell）
# === 1. 主脚本（不变，核心逻辑都在这里） ===
COPY scripts/show-login-info /usr/local/bin/show-login-info

# === 2. 触发器：兼容两种Shell场景 ===
# 场景A：登录Shell（如 su - dev、SSH登录）→ 保留原profile.d配置
COPY scripts/99-show-login-info.sh /etc/profile.d/99-show-login-info.sh
# 场景B：非登录交互式Shell（docker exec/bash、VSCode终端）→ 修改bashrc触发
RUN echo '#### 登录信息展示：非登录交互式Shell触发 ####' >> /etc/bash.bashrc && \
    echo 'if [[ $- == *i* ]] && [[ -z "${_LOGIN_INFO_SHOWN:-}" ]]; then' >> /etc/bash.bashrc && \
    echo '  # 调用主脚本展示登录信息' >> /etc/bash.bashrc && \
    echo '  /usr/local/bin/show-login-info;' >> /etc/bash.bashrc && \
    echo '  # 标记为已展示，避免子Shell重复触发（如再开一个终端标签）' >> /etc/bash.bashrc && \
    echo '  # 注意：这里不export，让每个终端会话独立' >> /etc/bash.bashrc && \
    echo '  _LOGIN_INFO_SHOWN=1;' >> /etc/bash.bashrc && \
    echo 'fi' >> /etc/bash.bashrc

# === 后续原有配置（时间同步、启动脚本等，不变） ===
# === 时间同步工具 & 每小时 cron 包装脚本 ===
COPY scripts/time-sync /usr/local/bin/time-sync
COPY scripts/ntp-sync /etc/cron.hourly/ntp-sync

# === 启动脚本（前台起 sshd + cron + 启动时同步一次时间） ===
COPY scripts/start.sh /usr/local/sbin/start.sh
ENTRYPOINT ["/bin/bash","/usr/local/sbin/start.sh"]

# === 工作目录 & 登录/非登录自动进入 /app ===
WORKDIR /app
COPY scripts/zzz-cd-app.sh /etc/profile.d/zzz-cd-app.sh
# 非登录交互式 bash 自动 cd /app（修改：使用不同的环境变量名）
RUN echo 'if [[ $- == *i* ]] && [[ -z "${_CD_APP_DONE:-}" ]] && [[ -d /app ]]; then cd /app; _CD_APP_DONE=1; fi' >> /etc/bash.bashrc

# === 统一修正：权限/CRLF/确保 profile.d 会被加载 & 关闭 MOTD ===
RUN set -eux; \
# 去CRLF
sed -i 's/\r$//' \
  /usr/local/bin/show-login-info \
  /etc/profile.d/99-show-login-info.sh \
  /usr/local/bin/time-sync \
  /etc/cron.hourly/ntp-sync \
  /usr/local/sbin/start.sh \
  /etc/profile.d/zzz-cd-app.sh || true; \
\
# 仅修改自定义脚本所在目录，不递归/usr
chown -R root:root /usr/local/bin /usr/local/sbin /etc/profile.d /etc/cron.hourly; \
chmod 0755 /usr/local/bin /usr/local/sbin /etc/profile.d /etc/cron.hourly; \
chmod 0755 /usr/local/bin/show-login-info /usr/local/bin/time-sync /usr/local/sbin/start.sh /etc/cron.hourly/ntp-sync; \
chmod 0644 /etc/profile.d/*.sh; \
\
# 后续加载profile.d、关闭MOTD的逻辑
grep -q '/etc/profile.d' /etc/profile || \
  printf '\n# Load /etc/profile.d/*.sh\nif [ -d /etc/profile.d ]; then\n  for f in /etc/profile.d/*.sh; do [ -r "$f" ] && . "$f"; done\n  unset f\nfi\n' >> /etc/profile; \
touch /root/.hushlogin /home/dev/.hushlogin || true; \
chown dev:dev /home/dev/.hushlogin 2>/dev/null || true; \
rm -f /etc/update-motd.d/10-help-text /etc/update-motd.d/50-motd-news || true; \
chmod -x /etc/update-motd.d/* 2>/dev/null || true; \
rm -f /run/motd.dynamic 2>/dev/null || true; \
: > /etc/motd || true; \
sed -i.bak -E 's/^(\s*session\s+optional\s+pam_motd\.so.*)$/# \1/' /etc/pam.d/sshd || true; \
sed -i.bak -E 's/^(\s*session\s+optional\s+pam_motd\.so.*)$/# \1/' /etc/pam.d/login || true; \
mkdir -p /etc/ssh/sshd_config.d; \
printf "PrintMotd no\nPrintLastLog no\n" > /etc/ssh/sshd_config.d/99-no-motd.conf

# ============================================================
# 容器入口
# ============================================================
EXPOSE 22 80 433 1000 2000 3000 8000 8080
CMD ["/start.sh"]