# 使用Ubuntu 22.04基础镜像
FROM ubuntu:22.04

# 禁用交互提示
ENV DEBIAN_FRONTEND=noninteractive
# 设置时区环境变量
ENV TZ=Asia/Shanghai

# 安装基础工具+登录信息显示所需软件，增加时区和时间同步工具
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
    && rm -rf /var/lib/apt/lists/*

# 配置时区为上海
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 配置bash-completion自动加载
RUN echo "source /etc/bash_completion" >> /etc/bash.bashrc

# 准备SSH环境
RUN ssh-keygen -A && mkdir -p /run/sshd && chmod 0755 /run/sshd

# 配置SSH允许root登录和密码认证
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# 设置用户密码并创建dev用户，明确指定home目录
# 免密sudo，开发更高效
RUN echo "root:dev" | chpasswd && \
    useradd -m -d /home/dev -s /bin/bash dev && \
    echo "dev:dev" | chpasswd && \
    echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    chown -R dev:dev /home/dev && \
    chmod 755 /home/dev

# 准备给挂载文件夹内所用内容777权限
RUN umask 0000 && \
    mkdir -p /home/test && \
    chown -R dev:dev /home/test && \
    chmod -R 777 /home/test && \
    ls -ld /home/test

# --------------------------
# 核心：配置登录后显示系统状态
# --------------------------
# 1. 编写自定义信息脚本
RUN echo '#!/bin/bash\n\
# 艺术字显示主机名（彩色）\n\
if command -v figlet &> /dev/null && command -v lolcat &> /dev/null; then\n\
    figlet -f slant "$(hostname)" | lolcat\n\
fi\n\
\n\
# 显示系统信息（neofetch）\n\
if command -v neofetch &> /dev/null; then\n\
    neofetch --stdout\n\
fi\n\
\n\
# 显示IP地址\n\
echo -e "\033[1;34mIP地址：\033[0m $(hostname -I | awk "{print \$1}")"\n\
\n\
# 显示当前时间\n\
echo -e "\033[1;32m当前时间：\033[0m $(date "+%Y-%m-%d %H:%M:%S")"\n\
\n\
' > /usr/local/bin/show-login-info && \
    chmod +x /usr/local/bin/show-login-info

# 2. 让bash启动时自动执行（对所有用户生效）
RUN echo "if [ -t 0 ]; then /usr/local/bin/show-login-info; fi" >> /etc/bash.bashrc
# 2. 禁用默认冗余提示（如广告、帮助文本）
RUN rm -f /etc/update-motd.d/10-help-text /etc/update-motd.d/50-motd-news

# 暴露SSH端口
EXPOSE 22

# 启动脚本 - 增加时间同步步骤
RUN echo "#!/bin/bash\n\
# 同步时间（使用阿里云NTP服务器）\n\
ntpdate ntp.aliyun.com || true\n\
# 启动SSH服务\n\
exec /usr/sbin/sshd -D" > /start.sh && chmod +x /start.sh

# 容器启动命令
CMD ["/start.sh"]