# ============================================================
# 基础环境阶段：系统初始化、APT源与包安装（优先执行）
# ============================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# 1️⃣ 更新APT并安装基础包（先拉包再做配置，缓存友好）
RUN apt update && apt install -y \
    apt-utils apt-file bash-completion \
    tzdata ntpdate cron \
    openssh-server sudo \
    net-tools iputils-ping \
    git curl wget \
    build-essential \
    python3 python3-pip python3-venv \
    nano vim \
    figlet lolcat neofetch btop screenfetch \
    && rm -rf /var/lib/apt/lists/*

# 2️⃣ 设置时区并初始化NTP
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \
    dpkg-reconfigure -f noninteractive tzdata && \
    mkdir -p /var/lib/ntp && touch /var/lib/ntp/ntp.drift && chmod 666 /var/lib/ntp/ntp.drift

# ============================================================
# Shell 环境优化：补全、显示信息、SSH初始化
# ============================================================

# 3️⃣ 启用bash自动补全
RUN echo "source /etc/bash_completion" >> /etc/bash.bashrc

# 4️⃣ 初始化SSH环境与配置
RUN ssh-keygen -A && mkdir -p /run/sshd && chmod 0755 /run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# 5️⃣ 创建dev用户 + 免密sudo + 默认密码
RUN echo "root:dev" | chpasswd && \
    useradd -m -d /home/dev -s /bin/bash dev && \
    echo "dev:dev" | chpasswd && \
    echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    chown -R dev:dev /home/dev && chmod 755 /home/dev

# ============================================================
# 运行环境与登录信息
# ============================================================

# 6️⃣ 创建测试与挂载目录
RUN umask 0000 && mkdir -p /app && \
    chown -R dev:dev /app && chmod -R 777 /app

# 7️⃣ 登录信息展示脚本
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
# APT缓存优化 & 自动补全修复
# ============================================================

# 8️⃣ 修复docker-clean，恢复apt补全
RUN echo "### 仅注释影响补全的配置项 ###" && \
    # 注释单行多配置
    sed -i 's/^Dir::Cache::pkgcache ""; Dir::Cache::srcpkgcache ""/\/\/ &/' /etc/apt/apt.conf.d/docker-clean && \
    # 兼容单行单独配置
    sed -i 's/^Dir::Cache::pkgcache "";/\/\/ &/' /etc/apt/apt.conf.d/docker-clean && \
    sed -i 's/^Dir::Cache::srcpkgcache "";/\/\/ &/' /etc/apt/apt.conf.d/docker-clean

# ============================================================
# 定时任务与启动逻辑
# ============================================================

# 9️⃣ 每小时同步时间任务
RUN echo '#!/bin/bash\n\
{ echo "=== 定时任务同步开始: $(date) ==="; \
  sudo ntpdate -v ntp.aliyun.com time1.aliyun.com ntp1.aliyun.com; \
  echo "=== 定时任务同步结束（状态：$?） ==="; } >> /var/log/ntp-sync.log 2>&1\n\
' > /etc/cron.hourly/ntp-sync && chmod +x /etc/cron.hourly/ntp-sync

# 🔟 容器启动时执行一次同步并启动sshd+cron
RUN echo "#!/bin/bash\n\
echo '容器启动时同步时间...'\n\
{ echo '=== 容器启动时同步开始: $(date) ==='; \
  sudo ntpdate -v ntp.aliyun.com time1.aliyun.com ntp1.aliyun.com; \
  echo '=== 容器启动时同步结束（状态：$?） ==='; } >> /var/log/ntp-sync.log 2>&1\n\
sudo service cron start\n\
exec /usr/sbin/sshd -D\n\
" > /start.sh && chmod +x /start.sh

# ============================================================
# 容器入口
# ============================================================

EXPOSE 22
CMD ["/start.sh"]
