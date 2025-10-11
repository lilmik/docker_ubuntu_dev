# 使用Ubuntu 22.04基础镜像
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# ------------------------------------------------------
# 1. 系统依赖（先安装，避免后面频繁重复下载）
# ------------------------------------------------------
RUN apt update && apt install -y \
    openssh-server \
    sudo \
    net-tools \
    iputils-ping \
    git \
    curl \
    wget \
    build-essential \
    btop \
    neofetch \
    bash-completion \
    nano \
    vim \
    figlet \
    lolcat \
    tzdata \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    xvfb \
    libgl1-mesa-glx \
    libgl1-mesa-dri \
    python3 \
    python3-pip \
    python3-venv \
    clang \
    cmake \
    ninja-build \
    pkg-config \
    libgtk-3-dev \
    liblzma-dev \
    chrony \
    chromium-browser \
    mesa-utils \
    apt-utils \
    apt-file \
    ntpdate \
    cron \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# 2. 设置时区并初始化NTP
# ============================================================
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \
    dpkg-reconfigure -f noninteractive tzdata && \
    mkdir -p /var/lib/ntp && touch /var/lib/ntp/ntp.drift && chmod 666 /var/lib/ntp/ntp.drift

# ============================================================
# 3. 用户和 SSH 环境
# ============================================================
RUN ssh-keygen -A && \
    mkdir -p /run/sshd && chmod 0755 /run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    echo "root:dev" | chpasswd && \
    if ! id -u dev >/dev/null 2>&1; then useradd -m -d /home/dev -s /bin/bash dev; fi && \
    echo "dev:dev" | chpasswd && \
    echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    mkdir -p /app/build && chown -R dev:dev /app /home/dev && chmod -R 777 /app

# ============================================================
# 4. Shell 环境优化：补全
# ============================================================
# bash-completion
RUN echo "source /etc/bash_completion" >> /etc/bash.bashrc

# 修复docker-clean，恢复apt补全
RUN echo "### 仅注释影响补全的配置项 ###" && \
    # 注释单行多配置
    sed -i 's/^Dir::Cache::pkgcache ""; Dir::Cache::srcpkgcache ""/\/\/ &/' /etc/apt/apt.conf.d/docker-clean && \
    # 兼容单行单独配置
    sed -i 's/^Dir::Cache::pkgcache "";/\/\/ &/' /etc/apt/apt.conf.d/docker-clean && \
    sed -i 's/^Dir::Cache::srcpkgcache "";/\/\/ &/' /etc/apt/apt.conf.d/docker-clean

# ============================================================
# 5. 下载 Flutter SDK 并预缓存
# ============================================================
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
# 6. 登录信息展示脚本
# ============================================================
RUN echo '#!/bin/bash\n\
if command -v figlet &> /dev/null && command -v lolcat &> /dev/null; then\n\
    figlet -f slant "$(hostname)" | lolcat\n\
fi\n\
if command -v neofetch &> /dev/null; then\n\
    neofetch --stdout | lolcat\n\
    # neofetch\n\
fi\n\
echo -e "\033[1;34mIP地址：\033[0m $(hostname -I | awk "{print \$1}")"\n\
echo -e "\033[1;32m当前时间：\033[0m $(date "+%Y-%m-%d %H:%M:%S")"\n\
echo -e "\033[1;35m当前时区：\033[0m $(cat /etc/timezone 2>/dev/null || date +%Z)"\n\
' > /usr/local/bin/show-login-info && chmod +x /usr/local/bin/show-login-info && \
    touch /var/log/ntp-sync.log && chmod 666 /var/log/ntp-sync.log && \
    echo "if [ -t 0 ]; then /usr/local/bin/show-login-info; fi" >> /etc/bash.bashrc && \
    rm -f /etc/update-motd.d/10-help-text /etc/update-motd.d/50-motd-news

# ============================================================
# 7. 定时任务与启动逻辑
# ============================================================
# 每小时同步时间任务
RUN echo '#!/bin/bash\n\
{ echo "=== 定时任务同步开始: $(date) ==="; \
  sudo ntpdate -v ntp.aliyun.com time1.aliyun.com ntp1.aliyun.com; \
  echo "=== 定时任务同步结束（状态：$?） ==="; } >> /var/log/ntp-sync.log 2>&1\n\
' > /etc/cron.hourly/ntp-sync && chmod +x /etc/cron.hourly/ntp-sync

# 容器启动时执行一次同步并启动sshd+cron
RUN echo "#!/bin/bash\n\
echo '容器启动时同步时间...'\n\
{ echo '=== 容器启动时同步开始: $(date) ==='; \
  sudo ntpdate -v ntp.aliyun.com time1.aliyun.com ntp1.aliyun.com; \
  echo '=== 容器启动时同步结束（状态：$?） ==='; } >> /var/log/ntp-sync.log 2>&1\n\
sudo service cron start\n\
exec /usr/sbin/sshd -D\n\
" > /start.sh && chmod +x /start.sh

# ============================================================
# 8. 容器入口
# ============================================================
EXPOSE 22
CMD ["/start.sh"]
