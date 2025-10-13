#!/bin/bash
# ---- 自动venv配置 - 用于 /etc/profile.d/ ----
case $- in *i*) ;; *) return ;; esac

# 保存原始PS1（只保存一次）
if [ -z "${_ORIGINAL_PS1_SAVED:-}" ]; then
    export _ORIGINAL_PS1="$PS1"
    export _ORIGINAL_PS1_SAVED=1
fi

# 全局deactivate函数，确保始终可用
deactivate() {
    if [ -z "${VIRTUAL_ENV:-}" ]; then
        echo "No virtual environment is active"
        return 1
    fi
    
    # 恢复PATH
    if [ -n "${_OLD_VIRTUAL_PATH:-}" ]; then
        export PATH="$_OLD_VIRTUAL_PATH"
        unset _OLD_VIRTUAL_PATH
    fi
    
    # 清除venv变量
    unset VIRTUAL_ENV
    unset VIRTUAL_ENV_PROMPT
    
    # 恢复PS1
    PS1="$_ORIGINAL_PS1"
    
    # 清除标记
    unset _AUTO_VENV_DONE
    
    # 重新定义deactivate函数，确保它仍然存在
    deactivate() {
        echo "No virtual environment is active"
        return 1
    }
}

# 自动激活默认venv
if [ -z "${_AUTO_VENV_DONE:-}" ] && [ -r /opt/venv/bin/activate ]; then
    # 保存原始PATH
    if [ -z "${_OLD_VIRTUAL_PATH:-}" ]; then
        export _OLD_VIRTUAL_PATH="$PATH"
    fi
    
    # 直接激活venv
    export VIRTUAL_ENV="/opt/venv"
    export PATH="/opt/venv/bin:$PATH"
    
    # 设置标记
    export _AUTO_VENV_DONE=1
fi

# 动态PS1更新函数，显示正确的虚拟环境名称
_venv_ps1_update() {
    # 重置为原始PS1
    PS1="$_ORIGINAL_PS1"
    
    # 如果在venv中，添加正确的环境名称
    if [ -n "${VIRTUAL_ENV:-}" ]; then
        local venv_name=$(basename "$VIRTUAL_ENV")
        PS1="($venv_name) $PS1"
    fi
    
    # 确保deactivate函数始终可用
    if ! type deactivate >/dev/null 2>&1; then
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
            PS1="$_ORIGINAL_PS1"
            unset _AUTO_VENV_DONE
            
            # 重新定义自己
            deactivate() {
                echo "No virtual environment is active"
                return 1
            }
        }
    fi
}

# 设置PROMPT_COMMAND
if [[ ";${PROMPT_COMMAND};" != *";_venv_ps1_update;"* ]]; then
    PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}_venv_ps1_update"
fi

# 立即更新一次
_venv_ps1_update