# 使用Ubuntu 22.04基础镜像
FROM ubuntu:22.04

# 禁用交互提示
ENV DEBIAN_FRONTEND=noninteractive
# 设置时区环境变量
ENV TZ=Asia/Shanghai

# 安装基础工具+时间同步依赖
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
    screenfetch \
    tzdata \
    ntpdate \
    cron \
    python3 python3-pip python3-venv \
    && rm -rf /var/lib/apt/lists/*

# 配置时区并初始化ntp相关文件
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \
    dpkg-reconfigure -f noninteractive tzdata && \
    mkdir -p /var/lib/ntp && touch /var/lib/ntp/ntp.drift && \
    chmod 666 /var/lib/ntp/ntp.drift

# 配置bash-completion自动加载
RUN echo "source /etc/bash_completion" >> /etc/bash.bashrc

# 准备SSH环境
RUN ssh-keygen -A && mkdir -p /run/sshd && chmod 0755 /run/sshd

# 配置SSH允许root登录和密码认证
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# 设置用户密码并创建dev用户（免密sudo）
RUN echo "root:dev" | chpasswd && \
    useradd -m -d /home/dev -s /bin/bash dev && \
    echo "dev:dev" | chpasswd && \
    echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    chown -R dev:dev /home/dev && \
    chmod 755 /home/dev

# 准备挂载文件夹
RUN umask 0000 && \
    mkdir -p /home/test && \
    chown -R dev:dev /home/test && \
    chmod -R 777 /home/test

# --------------------------
# 登录时仅显示系统信息（删除所有同步逻辑）
# --------------------------
RUN echo '#!/bin/bash\n\
# 仅显示系统信息，无时间同步操作\n\
if command -v figlet &> /dev/null && command -v lolcat &> /dev/null; then\n\
    figlet -f slant "$(hostname)" | lolcat\n\
fi\n\
if command -v neofetch &> /dev/null; then\n\
    neofetch --stdout\n\
fi\n\
echo -e "\033[1;34mIP地址：\033[0m $(hostname -I | awk "{print \$1}")"\n\
echo -e "\033[1;32m当前时间：\033[0m $(date "+%Y-%m-%d %H:%M:%S")"\n\
' > /usr/local/bin/show-login-info && \
    chmod +x /usr/local/bin/show-login-info && \
    touch /var/log/ntp-sync.log && chmod 666 /var/log/ntp-sync.log

# 让bash启动时自动执行
RUN echo "if [ -t 0 ]; then /usr/local/bin/show-login-info; fi" >> /etc/bash.bashrc && \
    rm -f /etc/update-motd.d/10-help-text /etc/update-motd.d/50-motd-news

# --------------------------
# 每小时定时同步（保持不变）
# --------------------------
RUN echo '#!/bin/bash\n\
{ echo "=== 定时任务同步开始: $(date) ==="; \
  sudo ntpdate -v ntp.aliyun.com time1.aliyun.com ntp1.aliyun.com; \
  echo "=== 定时任务同步结束（状态：$?） ==="; } >> /var/log/ntp-sync.log 2>&1\n\
' > /etc/cron.hourly/ntp-sync && \
    chmod +x /etc/cron.hourly/ntp-sync

# --------------------------
# 启动脚本（保持不变，容器启动时同步）
# --------------------------
RUN echo "#!/bin/bash\n\
echo '容器启动时同步时间...' \n\
{ echo "=== 容器启动时同步开始: $(date) ==="; \
  sudo ntpdate -v ntp.aliyun.com time1.aliyun.com ntp1.aliyun.com; \
  echo "=== 容器启动时同步结束（状态：$?） ==="; } >> /var/log/ntp-sync.log 2>&1\n\
\n\
sudo service cron start\n\
exec /usr/sbin/sshd -D\n\
" > /start.sh && chmod +x /start.sh

# 暴露SSH端口
EXPOSE 22

# 容器启动命令
CMD ["/start.sh"]