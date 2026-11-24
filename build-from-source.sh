#!/usr/bin/env bash
# ============================================================
# Komari 一键从源码构建（含「自动识别线路 + TCP 重传测试」改造）
#
# 用法（Linux / macOS / WSL）：
#
#  1) 只构建，不动现有服务（默认）——产物在 $WORK/src 下：
#     curl -fsSL https://raw.githubusercontent.com/tzb0w0/komari/main/build-from-source.sh | bash
#
#  2) 原地升级已安装的服务（需 root；自动备份旧二进制并重启 systemd）：
#     curl -fsSLO https://raw.githubusercontent.com/tzb0w0/komari/main/build-from-source.sh
#     sudo bash build-from-source.sh --upgrade
#
#  其他参数（用环境变量）：
#     OWNER=tzb0w0 BRANCH=main WORK=$HOME/komari-build ./build-from-source.sh
#     INSTALL_DIR=/opt/komari SERVICE_NAME=komari ./build-from-source.sh --upgrade
#
# 产物：
#   $WORK/src/komari/komari             服务端二进制
#   $WORK/src/komari-agent/komari-agent 探针二进制
#
# ⚠️ 升级只替换二进制，不会动数据目录（$INSTALL_DIR/data）。
#    切勿在别的目录直接运行 komari server —— 它会把 ./data 当成数据目录，
#    从而生成一个空库，看起来像「数据全丢了」。
# ============================================================
set -euo pipefail

OWNER="${OWNER:-tzb0w0}"
BRANCH="${BRANCH:-main}"
WORK="${WORK:-$HOME/komari-build}"
INSTALL_DIR="${INSTALL_DIR:-/opt/komari}"
SERVICE_NAME="${SERVICE_NAME:-komari}"
UPGRADE=false

for arg in "$@"; do
  case "$arg" in
    --upgrade) UPGRADE=true ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "未知参数: $arg（可用: --upgrade）" >&2; exit 2 ;;
  esac
done

info()  { printf '\033[32m[INFO]\033[0m %s\n' "$*"; }
warn()  { printf '\033[33m[WARN]\033[0m %s\n' "$*"; }
fail()  { printf '\033[31m[ERR ]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- 1. 依赖检查 ----------
info "检查依赖…"
need() { command -v "$1" >/dev/null 2>&1 || fail "缺少 $1，请先安装。$2"; }
need curl "例如: apt install -y curl"
need tar  "通常随系统自带"
need go   "https://go.dev/dl/ （需 1.25+）"
need node "https://nodejs.org/ （建议 >= 20）"
need npm  "通常随 node 一起安装"
command -v gcc >/dev/null 2>&1 || command -v cc >/dev/null 2>&1 \
  || fail "缺少 C 编译器（构建 SQLite 需要 CGO）。例如: apt install -y build-essential"

GO_VER=$(go env GOVERSION 2>/dev/null | sed 's/go//')
info "Go $GO_VER / Node $(node -v) / npm $(npm -v)"

# zstd 用于把前端产物打包给后端 embed
ZSTD_BIN=""
if command -v zstd >/dev/null 2>&1; then ZSTD_BIN="zstd"
elif python3 -c "import zstandard" >/dev/null 2>&1; then ZSTD_BIN="py"
else
  fail "缺少 zstd（后端要用它打包前端产物）。请安装：
    Debian/Ubuntu: sudo apt install -y zstd
    CentOS/RHEL:   sudo yum install -y zstd
    macOS:         brew install zstd
   或安装 python 包: pip install zstandard"
fi
info "zstd 打包方式: $ZSTD_BIN"

# ---------- 2. 下载三个仓库源码（纯 curl，无需 git） ----------
mkdir -p "$WORK/src"
pull() { # $1=repo
  local repo="$1" dir="$WORK/src/$1" tmp="$WORK/src/.$1.tmp"
  info "下载 $repo（${BRANCH}）…"
  rm -rf "$tmp"; mkdir -p "$tmp"
  # codeload 直出 tar.gz，等价于 GitHub 的 "Download ZIP"，不依赖 git
  curl -fsSL "https://codeload.github.com/$OWNER/$repo/tar.gz/refs/heads/$BRANCH" \
    | tar -xz -C "$tmp" --strip-components=1 \
    || fail "下载 $repo 失败（检查仓库名/分支/网络）"
  rm -rf "$dir"
  mv "$tmp" "$dir"
}
pull komari
pull komari-web
pull komari-agent

# ---------- 3. 构建前端 ----------
info "构建前端 komari-web（npm install + build，首次较慢）…"
cd "$WORK/src/komari-web"
if [ -f package-lock.json ]; then npm ci --no-audit --no-fund; else npm install --no-audit --no-fund; fi
npm run build

# ---------- 4. 打包前端产物并交给后端 ----------
info "打包前端产物 -> 后端 defaultTheme…"
THEME_DIR="$WORK/src/komari/web/public/defaultTheme"
mkdir -p "$THEME_DIR"
TAR_TMP="$(mktemp -t komari-dist-XXXXXX.tar)"
tar -cf "$TAR_TMP" -C "$WORK/src/komari-web/dist" .
if [ "$ZSTD_BIN" = "zstd" ]; then
  zstd -19 -T0 -f -q "$TAR_TMP" -o "$THEME_DIR/dist.tar.zst"
else
  python3 - "$TAR_TMP" "$THEME_DIR/dist.tar.zst" <<'PY'
import sys, zstandard
src, dst = sys.argv[1], sys.argv[2]
with open(src, 'rb') as f: data = f.read()
with open(dst, 'wb') as f:
    f.write(zstandard.ZstdCompressor(level=19).compress(data))
PY
fi
rm -f "$TAR_TMP"
cp "$WORK/src/komari-web/komari-theme.json" "$THEME_DIR/"
ls -lh "$THEME_DIR/dist.tar.zst" | awk '{print "  dist.tar.zst:", $5}'

# ---------- 5. 构建后端 ----------
info "构建后端 komari（CGO_ENABLED=1）…"
cd "$WORK/src/komari"
CGO_ENABLED=1 go build -trimpath -ldflags "-s -w" -o komari . || fail "后端构建失败"

# ---------- 6. 构建探针 ----------
info "构建探针 komari-agent…"
cd "$WORK/src/komari-agent"
CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o komari-agent . || fail "探针构建失败"

# ---------- 7. 完成 / 原地升级 ----------
BUILT_SERVER="$WORK/src/komari/komari"
BUILT_AGENT="$WORK/src/komari-agent/komari-agent"

if [ "$UPGRADE" = true ]; then
  info "开始原地升级（INSTALL_DIR=$INSTALL_DIR / SERVICE_NAME=$SERVICE_NAME）"

  [ "$(id -u)" -eq 0 ] || fail "升级需要 root 权限，请用 sudo 运行。"
  command -v systemctl >/dev/null 2>&1 || fail "未检测到 systemd，无法自动升级。请手动替换二进制。"

  # 从 systemd 单元里取真实二进制路径，取不到就用默认值
  TARGET_BIN=""
  UNIT="/etc/systemd/system/${SERVICE_NAME}.service"
  if [ -f "$UNIT" ]; then
    TARGET_BIN=$(grep -m1 '^ExecStart=' "$UNIT" | sed 's/^ExecStart=//' | awk '{print $1}')
  fi
  [ -n "$TARGET_BIN" ] || TARGET_BIN="$INSTALL_DIR/komari"

  if [ ! -f "$TARGET_BIN" ]; then
    fail "找不到已安装的二进制：$TARGET_BIN
如果你确认已安装，请显式指定：INSTALL_DIR=/你的路径 SERVICE_NAME=你的服务名 bash build-from-source.sh --upgrade
若这台机器本来就没装过，去掉 --upgrade 只做构建。"
  fi

  # 数据目录提示（只读检查，绝不修改）
  DATA_PATH="$(dirname "$TARGET_BIN")/data"
  if [ -d "$DATA_PATH" ]; then
    info "检测到数据目录：$DATA_PATH（本次不会改动）"
  else
    warn "未在 $DATA_PATH 找到 data 目录，请确认现有服务的数据位置。"
  fi

  BACKUP="${TARGET_BIN}.bak.$(date +%Y%m%d-%H%M%S)"
  info "备份旧二进制 -> $BACKUP"
  cp -p "$TARGET_BIN" "$BACKUP"

  # 保留权限、原子替换：先传临时文件再 mv，避免运行中写坏正在执行的映像
  info "替换二进制：$TARGET_BIN"
  install -m "$(stat -c '%a' "$TARGET_BIN" 2>/dev/null || echo 755)" "$BUILT_SERVER" "${TARGET_BIN}.new"
  mv -f "${TARGET_BIN}.new" "$TARGET_BIN"

  info "重启服务 ${SERVICE_NAME}.service"
  systemctl daemon-reload
  systemctl restart "${SERVICE_NAME}.service"
  sleep 3

  if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    info "升级完成，服务运行中。"
    echo
    echo "  服务状态: systemctl status ${SERVICE_NAME}"
    echo "  回滚方式: cp -p $BACKUP $TARGET_BIN && systemctl restart ${SERVICE_NAME}"
    echo "  数据目录: $DATA_PATH（未改动）"
    echo
    info "探针（$BUILT_AGENT）不在本机时无需处理；若本机也跑探针，请按同样方式替换其二进制。"
    exit 0
  else
    warn "服务未能正常启动，正在回滚…"
    cp -p "$BACKUP" "$TARGET_BIN"
    systemctl restart "${SERVICE_NAME}.service" || true
    fail "升级失败，已自动回滚到旧版本 $BACKUP。请查看：journalctl -u ${SERVICE_NAME} -n 60 --no-pager"
  fi
fi

cat <<EOF

$(printf '\033[32m构建完成\033[0m')

  服务端: $BUILT_SERVER
  探针:   $BUILT_AGENT

$(printf '\033[33m注意：这是「只构建」，没有安装也没有更新任何服务。\033[0m')

  已装过、想原地升级（需 root）：
    sudo bash $0 --upgrade
    （只替换二进制并重启，数据目录 $INSTALL_DIR/data 不动）

  全新安装 / 手动启动服务端：
    mkdir -p $INSTALL_DIR && cd $INSTALL_DIR
    cp $BUILT_SERVER . && ./komari server -l 0.0.0.0:25774
    首次访问 http://<你的IP>:25774 会进入安装引导，创建管理员账号。

  在被监控服务器上运行探针（用面板后台生成的 token）：
    $BUILT_AGENT --endpoint http://<面板地址>:25774 --token <TOKEN>

本改造新增的面板能力：
  · 服务器卡片自动显示探针识别出的出口线路（CN2 GIA / 9929 / 4837 / CMIN / 163）
  · 延迟下方新增 TCP 重传测试
  · 线路名由探针探测出口 IP 的 ASN 得出，全程无需手动填写

注意：探针需跑在支持 /proc/net/snmp 的 Linux 上才能采集重传率；
     其他平台会自动降级（显示 "-"），不影响其他功能。
EOF
