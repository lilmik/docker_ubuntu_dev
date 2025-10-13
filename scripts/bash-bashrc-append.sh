# ---- 非登录bash配置 ----
if [[ $- == *i* ]]; then
    # 保存原始PS1（只保存一次）
    if [ -z "${_ORIGINAL_PS1_SAVED:-}" ]; then
        export _ORIGINAL_PS1="$PS1"
        export _ORIGINAL_PS1_SAVED=1
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
        }
    fi

    # 自动激活默认venv
    if [ -z "${_AUTO_VENV_DONE:-}" ] && [ -d /etc/profile.d ]; then
        for profile in /etc/profile.d/*.sh; do
            if [ -r "$profile" ] && [[ "$profile" == *"zz-auto-venv.sh"* ]]; then
                source "$profile"
                break
            fi
        done
    fi

    # 动态PS1更新函数
    _venv_ps1_update() {
        PS1="$_ORIGINAL_PS1"
        if [ -n "${VIRTUAL_ENV:-}" ]; then
            local venv_name=$(basename "$VIRTUAL_ENV")
            PS1="($venv_name) $PS1"
        fi
    }

    # 设置PROMPT_COMMAND
    if [[ ";${PROMPT_COMMAND};" != *";_venv_ps1_update;"* ]]; then
        PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}_venv_ps1_update"
    fi
    
    # 立即更新一次
    _venv_ps1_update
fi
# ---- end ----