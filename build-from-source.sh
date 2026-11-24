#!/usr/bin/env bash
# ============================================================
# Komari 一键从源码构建（含「自动识别线路 + TCP 重传测试」改造）
#
# 用法（Linux / macOS / WSL）：
#   curl -fsSL https://raw.githubusercontent.com/tzb0w0/komari/main/build-from-source.sh | bash
#
# 或先下载再执行（可改参数）：
#   curl -fsSLO https://raw.githubusercontent.com/tzb0w0/komari/main/build-from-source.sh
#   chmod +x build-from-source.sh
#   OWNER=tzb0w0 WORK=$HOME/komari-build ./build-from-source.sh
#
# 产物：
#   $WORK/src/komari/komari            服务端二进制
#   $WORK/src/komari-agent/komari-agent 探针二进制
# ============================================================
set -euo pipefail

OWNER="${OWNER:-tzb0w0}"
BRANCH="${BRANCH:-main}"
WORK="${WORK:-$HOME/komari-build}"

info()  { printf '\033[32m[INFO]\033[0m %s\n' "$*"; }
warn()  { printf '\033[33m[WARN]\033[0m %s\n' "$*"; }
fail()  { printf '\033[31m[ERR ]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- 1. 依赖检查 ----------
info "检查依赖…"
need() { command -v "$1" >/dev/null 2>&1 || fail "缺少 $1，请先安装。$2"; }
need git  "例如: apt install -y git"
need go   "https://go.dev/dl/"
need node "https://nodejs.org/ (建议 >= 20)"
need npm  ""
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

# ---------- 2. 拉取三个仓库 ----------
mkdir -p "$WORK/src"
pull() { # $1=repo
  local dir="$WORK/src/$1"
  if [ -d "$dir/.git" ]; then
    info "更新 $1…"
    git -C "$dir" fetch --quiet origin "$BRANCH"
    git -C "$dir" reset --hard --quiet "origin/$BRANCH"
  else
    info "克隆 $1…"
    git clone --quiet --branch "$BRANCH" "https://github.com/$OWNER/$1.git" "$dir"
  fi
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

# ---------- 7. 完成 ----------
cat <<EOF

$(printf '\033[32m构建完成\033[0m')

  服务端: $WORK/src/komari/komari
  探针:   $WORK/src/komari-agent/komari-agent

启动服务端：
  cd $WORK/src/komari && ./komari server -l 0.0.0.0:25774
  首次访问 http://<你的IP>:25774 会进入安装引导，创建管理员账号。

在被监控服务器上运行探针（用面板后台生成的 token）：
  ./komari-agent --endpoint http://<面板地址>:25774 --token <TOKEN>

本改造新增的面板能力：
  · 服务器卡片自动显示探针识别出的出口线路（CN2 GIA / 9929 / 4837 / CMIN / 163）
  · 延迟下方新增 TCP 重传测试
  · 线路名由探针探测出口 IP 的 ASN 得出，全程无需手动填写

注意：探针需跑在支持 /proc/net/snmp 的 Linux 上才能采集重传率；
     其他平台会自动降级（显示 "-"），不影响其他功能。
EOF
