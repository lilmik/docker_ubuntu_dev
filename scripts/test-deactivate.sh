#!/bin/bash
echo "=== 测试deactivate命令持久性 ==="

echo "1. 检查deactivate命令:"
if type deactivate >/dev/null 2>&1; then
    echo "   ✓ deactivate命令可用"
else
    echo "   ✗ deactivate命令不可用"
    echo "   运行 'fix-deactivate' 修复"
    exit 1
fi

echo ""
echo "2. 测试默认venv:"
if [ -r "/opt/venv/bin/activate" ]; then
    source /opt/venv/bin/activate
    echo "   已激活默认venv，Python: $(which python)"
    deactivate
    echo "   已反激活"
else
    echo "   默认venv不存在"
fi

echo ""
echo "3. 检查deactivate命令是否仍然可用:"
if type deactivate >/dev/null 2>&1; then
    echo "   ✓ deactivate命令仍然可用"
else
    echo "   ✗ deactivate命令丢失"
fi

echo ""
echo "4. 测试自建venv:"
if command -v python >/dev/null 2>&1; then
    echo "   创建新虚拟环境..."
    sudo python -m venv /tmp/test_venv 2>/dev/null
    if [ -r "/tmp/test_venv/bin/activate" ]; then
        source /tmp/test_venv/bin/activate
        echo "   已激活新venv，Python: $(which python)"
        deactivate
        echo "   已反激活"
        
        # 清理
        sudo rm -rf /tmp/test_venv
    else
        echo "   创建新虚拟环境失败"
    fi
else
    echo "   Python不可用"
fi

echo ""
echo "5. 最终检查deactivate命令:"
if type deactivate >/dev/null 2>&1; then
    echo "   ✓ deactivate命令仍然可用"
else
    echo "   ✗ deactivate命令丢失"
    echo "   运行 'fix-deactivate' 修复"
fi

echo ""
echo "=== 测试完成 ==="