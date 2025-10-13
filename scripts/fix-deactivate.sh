#!/bin/bash
echo "修复deactivate命令..."

# 重新定义deactivate函数
deactivate() {
    if [ -z "${VIRTUAL_ENV:-}" ]; then
        echo "No virtual environment is active"
        return 1
    fi
    
    if [ -n "${_OLD_VIRTUAL_PATH:-}" ]; then
        export PATH="$_OLD_VIRTUAL_PATH"
        unset _OLD_VIRTUAL_PATH
    fi
    
    unset VIRTUAL_ENV
    unset VIRTUAL_ENV_PROMPT
    
    if [ -n "${_ORIGINAL_PS1:-}" ]; then
        PS1="$_ORIGINAL_PS1"
    fi
    
    unset _AUTO_VENV_DONE
    
    # 重新定义deactivate函数
    deactivate() {
        echo "No virtual environment is active"
        return 1
    }
}

echo "deactivate命令已修复"
echo "测试: deactivate"