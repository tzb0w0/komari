#!/bin/bash
# ============================================================
# Komari 简洁安装 / 升级脚本（无交互菜单、无广告）
#
#   curl -fsSL https://raw.githubusercontent.com/tzb0w0/komari/main/install.sh | bash
#
# 参数（都可选，不填用默认值）：
#   --port N        监听端口，默认 25774
#   --dir PATH      安装目录，默认 /opt/komari
#   --version TAG   指定版本，默认 latest
#   --no-start      只安装不启动
#   --help
#
# 已安装时会自动备份旧二进制并在原地升级，数据目录 $DIR/data 不受影响。
# ============================================================
set -euo pipefail

REPO="tzb0w0/komari"
INSTALL_DIR="/opt/komari"
PORT="25774"
VERSION="latest"
NO_START="0"

while [ $# -gt 0 ]; do
    case "$1" in
        --port)     PORT="${2:?--port 需要端口号}"; shift 2 ;;
        --dir)      INSTALL_DIR="${2:?--dir 需要路径}"; shift 2 ;;
        --version)  VERSION="${2:?--version 需要标签}"; shift 2 ;;
        --no-start) NO_START="1"; shift ;;
        -h|--help)  sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "未知参数: $1（--help 查看用法）" >&2; exit 2 ;;
    esac
done

C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_OFF=$'\033[0m'
info() { printf '%s[INFO]%s %s\n' "$C_OK" "$C_OFF" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_WARN" "$C_OFF" "$*"; }
die()  { printf '%s[ERR ]%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "需要 root 权限，请用 sudo 运行。"
command -v curl >/dev/null 2>&1 || die "缺少 curl。"
command -v systemctl >/dev/null 2>&1 || [ "$NO_START" = "1" ] || die "未检测到 systemd，无法创建服务；可加 --no-start 只安装。"

case "$(uname -m)" in
    x86_64|amd64)  ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) die "暂不支持的架构：$(uname -m)（目前提供 amd64 / arm64）" ;;
esac

if [ "$VERSION" = "latest" ]; then
    DL="https://github.com/${REPO}/releases/latest/download/komari-linux-${ARCH}"
else
    DL="https://github.com/${REPO}/releases/download/${VERSION}/komari-linux-${ARCH}"
fi

BIN="${INSTALL_DIR}/komari"
EXISTING="0"
[ -f "$BIN" ] && EXISTING="1"

info "架构 ${ARCH} / 目录 ${INSTALL_DIR} / 端口 ${PORT}"
mkdir -p "$INSTALL_DIR"

# ---- 下载到临时文件，避免写坏正在运行的二进制 ----
TMP="$(mktemp "${INSTALL_DIR}/.komari.download.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
info "下载 ${DL}"
curl -fL --progress-bar -o "$TMP" "$DL" || die "下载失败，请检查网络或版本号。"
[ -s "$TMP" ] || die "下载文件为空。"
chmod 755 "$TMP"

if [ "$EXISTING" = "1" ]; then
    BACKUP="${BIN}.bak.$(date +%Y%m%d-%H%M%S)"
    cp -p "$BIN" "$BACKUP"
    info "已备份旧版本：${BACKUP}"
fi

mv -f "$TMP" "$BIN"
trap - EXIT
info "二进制已就位：${BIN}"

# ---- systemd ----
if [ "$NO_START" = "0" ]; then
    SERVICE="/etc/systemd/system/komari.service"
    cat > "$SERVICE" <<EOF
[Unit]
Description=Komari Monitor Service
After=network.target

[Service]
Type=simple
Environment="GODEBUG=disablethp=1"
ExecStart=${BIN} server -l 0.0.0.0:${PORT}
WorkingDirectory=${INSTALL_DIR}
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable komari >/dev/null 2>&1 || true
    systemctl restart komari || die "服务启动失败，查看：journalctl -u komari -n 50 --no-pager"
    sleep 2
    if systemctl is-active --quiet komari; then
        info "服务运行中。"
    else
        warn "服务未处于 running 状态，请检查：journalctl -u komari -n 50 --no-pager"
        [ "$EXISTING" = "1" ] && [ -n "${BACKUP:-}" ] && warn "如需回滚：cp -p ${BACKUP} ${BIN} && systemctl restart komari"
    fi
fi

# ---- 访问地址提示 ----
IP="$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')"
echo
if [ "$EXISTING" = "1" ]; then
    info "升级完成（数据目录 ${INSTALL_DIR}/data 未改动）"
else
    info "安装完成"
fi
echo "  访问地址： http://${IP:-<服务器IP>}:${PORT}"
[ "$EXISTING" = "0" ] && echo "  首次访问会进入安装引导，创建管理员账号。"
echo "  数据目录： ${INSTALL_DIR}/data"
echo "  服务管理： systemctl {status|start|stop|restart} komari"
echo "  查看日志： journalctl -u komari -f"
[ "$EXISTING" = "1" ] && [ -n "${BACKUP:-}" ] && echo "  回滚命令： cp -p ${BACKUP} ${BIN} && systemctl restart komari"
