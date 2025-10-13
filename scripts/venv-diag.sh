#!/bin/bash
echo "=== Venv诊断信息 ==="
echo "用户: $(whoami)"
echo "Python路径: $(which python 2>/dev/null || echo '未找到')"
echo "VIRTUAL_ENV: ${VIRTUAL_ENV:-未设置}"
echo "_AUTO_VENV_DONE: ${_AUTO_VENV_DONE:-未设置}"

# 检查deactivate函数是否存在
if declare -f deactivate >/dev/null 2>&1; then
    echo "deactivate函数: 已定义"
else
    echo "deactivate函数: 未定义"
fi

# 检查venv激活状态
if [ -n "${VIRTUAL_ENV:-}" ]; then
    echo "虚拟环境状态: 已激活 ($VIRTUAL_ENV)"
    echo "Venv Python版本: $($VIRTUAL_ENV/bin/python --version 2>&1)"
else
    echo "虚拟环境状态: 未激活"
fi

# 检查PATH中venv的位置
if echo "$PATH" | grep -q "/opt/venv/bin"; then
    echo "PATH中的venv: 存在"
    PATH_POSITION=$(echo "$PATH" | tr ':' '\n' | grep -n "/opt/venv/bin" | head -1)
    echo "Venv在PATH中的位置: $PATH_POSITION"
else
    echo "PATH中的venv: 不存在"
fi

echo "=== 环境信息 ==="
echo "SHELL: $SHELL"
echo "TERM: $TERM"
echo "TERM_PROGRAM: ${TERM_PROGRAM:-未设置}"
echo "当前目录: $(pwd)"

echo "=== 测试命令 ==="
echo "1. 检查Python: which python"
echo "2. 退出venv: deactivate"
echo "3. 手动激活: source /opt/venv/bin/activate"