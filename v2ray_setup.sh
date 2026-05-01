#!/bin/bash

# V2Ray 一键安装脚本 for Ubuntu
# 功能：自动安装、配置、优化 V2Ray 代理节点
# 版本：1.0.0

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 错误处理
set -e
trap 'log_error "脚本执行失败，请检查错误信息"' ERR

# 检查是否为root用户
if [[ $EUID -ne 0 ]]; then
   log_error "此脚本必须以root用户身份运行"
   exit 1
fi

# 检查系统版本
if ! grep -q "Ubuntu" /etc/issue; then
    log_error "此脚本仅支持Ubuntu系统"
    exit 1
fi

# 获取系统信息
ARCH=$(arch)
if [[ "$ARCH" != "x86_64" ]]; then
    log_warn "检测到非x86_64架构，可能影响兼容性"
fi

# 生成随机密码
generate_password() {
    openssl rand -base64 32 | tr -d '=' | tr -d '+' | tr -d '/'
}

# 生成UUID
generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# 主安装函数
install_v2ray() {
    log_info "开始安装 V2Ray..."

    # 更新系统
    log_info "更新系统软件包..."
    apt update && apt upgrade -y

    # 安装必要工具
    log_info "安装必要工具..."
    apt install -y curl wget unzip tar gzip vim net-tools ufw

    # 下载并安装 V2Ray
    log_info "下载 V2Ray 安装脚本..."
    bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)

    # 创建配置目录
    mkdir -p /etc/v2ray/config

    # 生成配置
    log_info "生成 V2Ray 配置..."
    local PORT=${1:-10086}
    local UUID=${2:-$(generate_uuid)}
    local WS_PATH=${3:-"/v2ray"}
    local ALTER_ID=${4:-0}

    # 创建配置文件
    cat > /etc/v2ray/config/config.json <<EOF
{
  "inbounds": [
    {
      "port": ${PORT},
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "alterId": ${ALTER_ID},
            "security": "auto"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "${WS_PATH}",
          "headers": {}
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": []
  }
}
EOF

    # 创建 systemd 服务文件
    log_info "配置系统服务..."
    cat > /etc/systemd/system/v2ray.service <<EOF
[Unit]
Description=V2Ray Service
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
ExecStart=/usr/local/bin/v2ray -config /etc/v2ray/config/config.json
Restart=on-failure
RestartSec=3s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载 systemd
    systemctl daemon-reload

    # 配置防火墙
    configure_firewall

    # 配置BBR优化
    configure_bbr

    # 启动服务
    log_info "启动 V2Ray 服务..."
    systemctl enable v2ray
    systemctl start v2ray

    # 获取服务器IP
    local IP=$(curl -s ipv4.icanhazip.com)
    if [[ -z "$IP" ]]; then
        IP=$(curl -s ipinfo.io/ip)
    fi

    # 显示配置信息
    show_config "$IP" "$PORT" "$UUID" "$WS_PATH"
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙..."

    # 开放SSH端口
    ufw allow 22/tcp

    # 开放V2Ray端口（默认10086）
    local port=$(grep '"port"' /etc/v2ray/config/config.json | awk '{print $2}' | tr -d '",')
    ufw allow ${port}/tcp
    ufw allow ${port}/udp

    # 开放80和443端口（用于伪装）
    ufw allow 80/tcp
    ufw allow 443/tcp

    # 设置默认策略
    ufw default deny incoming
    ufw default allow outgoing

    # 启用防火墙（不交互式确认）
    echo "y" | ufw enable
}

# 配置BBR优化
configure_bbr() {
    log_info "配置网络优化..."

    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
        cat >> /etc/sysctl.conf <<EOF
# BBR Optimization
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=30
EOF
    fi

    # 应用配置
    sysctl -p
}

# 显示配置信息
show_config() {
    local IP=$1
    local PORT=$2
    local UUID=$3
    local WS_PATH=$4

    log_info "V2Ray 安装完成！"
    echo
    echo "========================================"
    echo "V2Ray 配置信息"
    echo "========================================"
    echo "地址 (Address): $IP"
    echo "端口 (Port): $PORT"
    echo "用户ID (UUID): $UUID"
    echo "额外ID (Alter ID): 0"
    echo "传输协议 (Network): ws"
    echo "路径 (Path): $WS_PATH"
    echo "加密方式 (Security): auto"
    echo "========================================"
    echo
    echo "========================================"
    echo "📱 数码解码频道 - 专业科技资讯"
    echo "🔔 关注获取最新科技动态"
    echo "📺 频道：@shuma_decode"
    echo "========================================"
    echo

    # 生成VMess链接
    local VMESS_LINK="vmess://$(echo -n "auto:$UUID@$IP:$PORT?path=$WS_PATH&security=none&type=ws" | base64 -w 0)"
    echo "VMess 链接:"
    echo "$VMESS_LINK"
    echo

    # 生成配置二维码（如果安装了qrencode）
    if command -v qrencode &> /dev/null; then
        log_info "生成配置二维码..."
        qrencode -t ANSIUTF8 "$VMESS_LINK"
    else
        log_warn "未找到 qrencode，无法生成二维码"
        log_info "可以手动安装：apt install qrencode"
    fi

    echo
    log_info "管理命令："
    echo "启动: systemctl start v2ray"
    echo "停止: systemctl stop v2ray"
    echo "重启: systemctl restart v2ray"
    echo "状态: systemctl status v2ray"
    echo "日志: journalctl -u v2ray -f"
    echo

    log_info "配置文件位置: /etc/v2ray/config/config.json"
    log_info "如需修改配置，请编辑配置文件后重启服务"
}

# 卸载函数
uninstall_v2ray() {
    log_info "开始卸载 V2Ray..."

    # 停止服务
    systemctl stop v2ray 2>/dev/null || true
    systemctl disable v2ray 2>/dev/null || true

    # 备份卸载脚本
    bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh) --remove

    # 删除配置
    rm -rf /etc/v2ray

    # 删除服务文件
    rm -f /etc/systemd/system/v2ray.service

    # 重新加载 systemd
    systemctl daemon-reload

    log_info "V2Ray 已卸载"
}

# 更新函数
update_v2ray() {
    log_info "开始更新 V2Ray..."

    # 停止服务
    systemctl stop v2ray

    # 更新 V2Ray
    bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)

    # 启动服务
    systemctl start v2ray

    log_info "V2Ray 更新完成"
}

# 主菜单
show_menu() {
    echo "========================================"
    echo "V2Ray 一键安装脚本 for Ubuntu"
    echo "========================================"
    echo "1. 安装 V2Ray"
    echo "2. 卸载 V2Ray"
    echo "3. 更新 V2Ray"
    echo "4. 查看配置"
    echo "5. 重启服务"
    echo "6. 查看日志"
    echo "7. 退出"
    echo "========================================"
}

# 显示使用帮助
show_help() {
    echo "使用方法: $0 [选项]"
    echo
    echo "选项:"
    echo "  -i, --install     安装 V2Ray"
    echo "  -u, --uninstall   卸载 V2Ray"
    echo "  -U, --update      更新 V2Ray"
    echo "  -c, --config      查看配置"
    echo "  -r, --restart     重启服务"
    echo "  -l, --log         查看日志"
    echo "  -h, --help        显示帮助"
    echo
    echo "示例:"
    echo "  $0 --install      # 一键安装"
    echo "  $0 --uninstall    # 一键卸载"
    echo "  $0 --config       # 查看配置"
}

# 参数解析
case "$1" in
    -i|--install)
        # 生成随机配置
        PORT=$(shuf -i 10000-60000 -n 1)
        UUID=$(generate_uuid)
        WS_PATH="/$(openssl rand -hex 6)"

        install_v2ray "$PORT" "$UUID" "$WS_PATH"
        ;;
    -u|--uninstall)
        uninstall_v2ray
        ;;
    -U|--update)
        update_v2ray
        ;;
    -c|--config)
        if [[ -f /etc/v2ray/config/config.json ]]; then
            CONFIG=$(cat /etc/v2ray/config/config.json | grep -o '"id": "[^"]*' | cut -d'"' -f4)
            PORT=$(cat /etc/v2ray/config/config.json | grep -o '"port": [0-9]*' | cut -d' ' -f2)
            WS_PATH=$(cat /etc/v2ray/config/config.json | grep -o '"path": "[^"]*' | cut -d'"' -f4)
            IP=$(curl -s ipv4.icanhazip.com)
            show_config "$IP" "$PORT" "$CONFIG" "$WS_PATH"
        else
            log_error "V2Ray 未安装或配置文件丢失"
        fi
        ;;
    -r|--restart)
        log_info "重启 V2Ray 服务..."
        systemctl restart v2ray
        log_info "服务已重启"
        ;;
    -l|--log)
        log_info "显示 V2Ray 日志 (按 Ctrl+C 退出)..."
        journalctl -u v2ray -f
        ;;
    -h|--help)
        show_help
        ;;
    *)
        # 显示交互式菜单
        while true; do
            show_menu
            read -p "请选择操作 [1-7]: " choice

            case $choice in
                1)
                    bash "$0" --install
                    break
                    ;;
                2)
                    bash "$0" --uninstall
                    break
                    ;;
                3)
                    bash "$0" --update
                    break
                    ;;
                4)
                    bash "$0" --config
                    break
                    ;;
                5)
                    bash "$0" --restart
                    break
                    ;;
                6)
                    bash "$0" --log
                    break
                    ;;
                7)
                    echo "退出脚本"
                    exit 0
                    ;;
                *)
                    log_error "无效的选择，请重新输入"
                    ;;
            esac
        done
        ;;
esac

exit 0