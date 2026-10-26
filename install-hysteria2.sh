#!/usr/bin/env bash

# 确保以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "[-] 请使用 root 权限运行此脚本 (sudo -i)"
    exit 1
fi

echo "=========================================="
echo "    Hysteria 2 服务端自动化安装与配置     "
echo "=========================================="

# 1. 检查并安装依赖
echo "[+] 正在检查系统依赖 (curl, wget, jq, openssl)..."
if command -v apt &> /dev/null; then
    apt update && apt install -y curl wget jq openssl
elif command -v yum &> /dev/null; then
    yum install -y curl wget jq openssl
fi

# 2. 获取 GitHub Releases 最新版本信息
echo "[+] 正在获取 Hysteria 最新版本..."
LATEST_TAG=$(curl -s https://api.github.com/repos/HyNetworks/hysteria/releases/latest | jq -r .tag_name)
if [ -z "$LATEST_TAG" ] || [ "$LATEST_TAG" == "null" ]; then
    echo "[-] 获取最新版本失败，将尝试使用官方快捷安装脚本..."
    bash <(curl -fsSL https://get.hysteria.network/install.sh)
    exit 0
fi

echo "[+] 检测到最新版本: ${LATEST_TAG}"

# 3. 判断系统架构
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        BINARY_NAME="hysteria-linux-amd64"
        ;;
    aarch64 | arm64)
        BINARY_NAME="hysteria-linux-arm64"
        ;;
    *)
        echo "[-] 不支持的系统架构: $ARCH"
        exit 1
        ;;
esac

DOWNLOAD_URL="https://github.com/HyNetworks/hysteria/releases/download/${LATEST_TAG}/${BINARY_NAME}"

# 4. 下载并安装二进制文件
echo "[+] 正在下载服务端核心: $DOWNLOAD_URL"
curl -L -o /usr/local/bin/hysteria "$DOWNLOAD_URL"
chmod +x /usr/local/bin/hysteria

# 5. 创建配置与日志目录
echo "[+] 正在初始化配置文件目录..."
mkdir -p /etc/hysteria
mkdir -p /var/log/hysteria

# 6. 交互式获取配置参数
echo "------------------------------------------"
read -p "请输入 Hysteria 2 监听端口 [默认 443]: " HY_PORT
HY_PORT=${HY_PORT:-443}

read -p "请输入连接密码 (Password): " HY_PASS
while [ -z "$HY_PASS" ]; do
    read -p "密码不能为空，请重新输入连接密码: " HY_PASS
done
echo "------------------------------------------"

# 7. 生成自签 SSL 证书
echo "[+] 正在生成自签 SSL 证书..."
openssl ecparam -genkey -name prime256v1 -out /etc/hysteria/server.key
openssl req -new -x509 -days 3650 -key /etc/hysteria/server.key -out /etc/hysteria/server.crt -subj "/CN=www.bing.com"

# 8. 写入配置文件
echo "[+] 正在写入配置文件 /etc/hysteria/config.yaml..."
cat << EOF > /etc/hysteria/config.yaml
listen: 0.0.0.0:${HY_PORT}

auth:
  type: password
  password: "${HY_PASS}"

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com/
    rewriteHost: true
EOF

# 9. 创建 Systemd 服务管理
echo "[+] 正在配置 Systemd 服务..."
cat << 'EOF' > /etc/systemd/system/hysteria-server.service
[Unit]
Description=Hysteria 2 Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/hysteria
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hysteria-server
systemctl restart hysteria-server

echo "=========================================="
echo "[+] Hysteria 2 安装与配置成功完成！"
echo "[*] 监听端口: ${HY_PORT}"
echo "[*] 连接密码: ${HY_PASS}"
echo "[*] 配置文件路径: /etc/hysteria/config.yaml"
echo "[*] 服务状态: $(systemctl is-active hysteria-server)"
echo "=========================================="