# Komari（定制分支：自动线路识别 + TCP 重传测试）

基于 [Komari](https://github.com/komari-monitor/komari) 的定制分支，在原有服务器监控面板基础上新增两项能力：

- **自动识别出口线路**：探针探测本机出口 IP，查其 ASN，自动判定线路（CN2 GIA / 9929 / 4837 / CMIN / 163），显示在服务器卡片上。**全程无需手动填写**。
- **TCP 重传测试**：展示 TCP 重传率、重传报文数、发送报文数，位于延迟信息下方。

> 原版 README 已移除，本文档为本分支唯一的部署与使用说明。

---

## 一、快速开始（推荐：预编译二进制，和原版一样）

在**面板服务器**上执行一条命令：

```bash
curl -fsSL https://raw.githubusercontent.com/tzb0w0/komari/main/install-komari.sh | bash
```

这就是**原版官方安装器**（TUI 向导、systemd 服务、升级/备份一应俱全），本分支仅把下载源指向自己的 release，所以：

- **不需要安装 go / node / gcc**，只依赖 `curl` + `tar`（系统一般自带）
- 自动识别架构（amd64 / arm64）
- 安装到 `/opt/komari`，服务名 `komari`，默认端口 `25774`
- 首次启动后浏览器访问 `http://<IP>:25774` 走安装引导

支持的架构：`linux amd64`、`linux arm64`（其他平台请用下面的源码构建方式）。

> 交互说明：脚本已固定从 `/dev/tty` 读取选项，所以 `curl ... | bash` 也能正常选择菜单。
> 若所在环境没有终端（如某些自动化面板），请改为先下载再运行：
> ```bash
> curl -fsSLO https://raw.githubusercontent.com/tzb0w0/komari/main/install-komari.sh
> sudo bash install-komari.sh
> ```

> 想指定目录 / 端口 / 跳过 TUI：直接运行脚本并加参数，例如
> `curl -fsSLO https://raw.githubusercontent.com/tzb0w0/komari/main/install-komari.sh && sudo bash install-komari.sh --install-dir /opt/komari`

---

## 一（附）、可选：从源码自己编译

只有在需要改代码、或要在本分支未提供二进制的平台上运行时才需要。**这条路需要完整编译环境**（go ≥1.25、node ≥20、gcc、zstd），服务器上没装就别走这条。

```bash
curl -fsSL https://raw.githubusercontent.com/tzb0w0/komari/main/build-from-source.sh | bash
```

脚本会自动完成：依赖检查 → 下载三个仓库源码 → 构建前端 → 打包主题 → 编译服务端与探针。

产物位置：

| 产物 | 路径 |
|---|---|
| 服务端二进制 | `~/komari-build/src/komari/komari` |
| 探针二进制 | `~/komari-build/src/komari-agent/komari-agent` |

**依赖要求：**

| 依赖 | 说明 |
|---|---|
| curl / tar | 下载并解压源码（不再需要 git） |
| node（≥20）/ npm | 构建前端 |
| go（≥1.25） | 构建后端与探针 |
| gcc / cc | SQLite 需要 CGO，**必须**有 C 编译器 |
| zstd | 打包前端产物给后端 embed |

Debian/Ubuntu 一把装齐：

```bash
sudo apt update && sudo apt install -y curl build-essential zstd
# node 与 go 请按官方方式安装（https://nodejs.org 、https://go.dev/dl）
```

> 重复执行同一命令即为**重新下载并构建**。
> 注意：源码构建产出的二进制不含预编译包里的版本信息，仅建议用于开发验证。

---

## 二、启动与初始化

## 二、启动与初始化

> **如果你用的是上面的 `install-komari.sh` 安装器，这一步已经自动完成了**：二进制在 `/opt/komari/komari`，systemd 服务已创建并启动，直接访问 `http://<服务器IP>:25774` 即可。
> 以下内容适用于「源码自行编译」或「手动部署」的情况。

```bash
mkdir -p /opt/komari && cd /opt/komari
cp ~/komari-build/src/komari/komari .
./komari server -l 0.0.0.0:25774
```

首次访问 `http://<服务器IP>:25774` 会进入**安装引导**，创建管理员账号并完成初始化。

> ⚠️ **数据目录跟随「当前工作目录」**。Komari 把数据存在 `./data`，所以必须在固定目录（如 `/opt/komari`）下启动。若换到别的目录启动，会出现一个空数据库，看起来像「数据全丢了」（原数据其实还在旧目录）。

---

## 三、安装为系统服务（systemd）

```ini
# /etc/systemd/system/komari.service
[Unit]
Description=Komari Monitor Service
After=network.target

[Service]
Type=simple
Environment="GODEBUG=disablethp=1"
ExecStart=/opt/komari/komari server -l 0.0.0.0:25774
WorkingDirectory=/opt/komari
Restart=always
User=root

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now komari
sudo systemctl status komari
```

> `WorkingDirectory=/opt/komari` 决定了数据目录是 `/opt/komari/data`，**不要删改**。

---

## 四、升级（原地更新，保留数据）

### 方式 A：用官方安装器升级（推荐，无需编译环境）

再次运行安装器即可，它会备份当前版本、下载新二进制并重启服务：

```bash
curl -fsSL https://raw.githubusercontent.com/tzb0w0/komari/main/install-komari.sh | bash
```

### 方式 B：源码构建后升级（需编译环境）

```bash
curl -fsSLO https://raw.githubusercontent.com/tzb0w0/komari/main/build-from-source.sh
sudo bash build-from-source.sh --upgrade
```

`--upgrade` 的行为：

1. 从 systemd 单元文件解析**真实的二进制路径**（不靠猜测）
2. 备份旧二进制为 `komari.bak.<时间戳>`
3. 先写 `.new` 再原子 `mv` 替换，避免写坏正在运行的映像
4. `systemctl daemon-reload && systemctl restart komari`
5. 健康检查；**启动失败会自动回滚**到备份

**数据目录不会被修改。**

自定义安装位置时：

```bash
sudo INSTALL_DIR=/www/komari SERVICE_NAME=komari bash build-from-source.sh --upgrade
```

### 手动回滚

```bash
sudo cp -p /opt/komari/komari.bak.20261124-173000 /opt/komari/komari
sudo systemctl restart komari
```

---

## 五、给被监控服务器装探针（一键）

### 推荐：面板生成命令（自动绑定）

1. 面板 → **设置** → 复制「自动发现密钥」（需 ≥12 位，为空则先设置）
2. 面板 → **服务器** → **自动发现** → 复制生成的命令
3. 粘贴到目标服务器执行

执行后探针会自动向面板注册并绑定，凭据写入二进制同目录的 `auto-discovery.json`，**无需手动创建或填写 token**。

### 手动方式

```bash
# 方式 A：安装脚本（已指向本分支，装的就是定制版）
curl -fsSL https://raw.githubusercontent.com/tzb0w0/komari-agent/main/install.sh | bash -s -- \
  --auto-discovery "<自动发现密钥>" --endpoint "http://<面板IP>:25774"

# 方式 B：直接运行编译好的二进制
./komari-agent --endpoint "http://<面板IP>:25774" --auto-discovery "<自动发现密钥>"
```

也可以使用 token 方式（面板手动创建节点后获取 token）：

```bash
./komari-agent --endpoint "http://<面板IP>:25774" --token "<TOKEN>"
```

探针默认安装目录 `/opt/komari/agent`，服务名 `komari-agent`。

---

## 六、仓库结构（为什么是三个仓库）

沿用上游 Komari 的架构，源码分三个仓库：

| 仓库 | 角色 | 是否需要单独部署 |
|---|---|---|
| `komari`（本仓库） | 服务端（Go，**内含前端网页**） | 是，1 台 |
| [komari-web](https://github.com/tzb0w0/komari-web) | 前端主题（React） | 否，构建后嵌入服务端 |
| [komari-agent](https://github.com/tzb0w0/komari-agent) | 探针（Go） | 是，每台被监控机器 |

**实际只需要运行两个二进制**：服务端 + 探针。前端只是源码，其构建产物会被打进服务端。

---

## 七、本分支的改动点

| 仓库 | 文件 | 改动 |
|---|---|---|
| agent | `monitoring/unit/line.go`（新增） | 出口 IP → ASN → 线路判定，缓存 30 分钟 |
| agent | `monitoring/unit/retransmit.go`（新增） | 读 `/proc/net/snmp` 计算区间 TCP 重传率 |
| agent | `monitoring/monitoring.go` | report 增加 `retransmit` 字段 |
| agent | `server/basicInfo.go` | basicInfo 增加 `line` 字段 |
| agent | `update/update.go` | `Repo` 指向本分支，避免自动更新覆盖成官方版 |
| agent | `install.sh` / `install.ps1` | 下载地址指向本分支 |
| 服务端 | `database/models/models.go` | Client 增加 `LineInfo`（`line_info`） |
| 服务端 | `web/api/client/uploadBasicInfo.go` | 上报时序列化 `line` 入 `line_info` |
| 服务端 | `protocol/v2/jsonrpc.go` | `Report` 增加 `RetransmitReport` |
| 服务端 | `web/rpc/jsonrpc/common.go` | `recordLike` 透传 `retransmit` |
| 前端 | `src/components/LineQualityPanel.tsx`（新增） | 线路徽章 + 重传测试区（纯展示，无输入控件） |
| 前端 | `Node.tsx` / `NodeListContext.tsx` / `LiveDataContext.tsx` / `LiveData.tsx` | 数据管道接入 |
| 前端 | `installCommand.ts` | 面板一键命令指向本分支 |
| 前端 | `zh_CN.json` / `en.json` | 新增 `lineQuality` 词条 |

线路判定规则：

| ASN | 线路 |
|---|---|
| 4809 / 4812 / 4816 | CN2 GIA |
| 9929 | 9929 |
| 4837 | 4837 |
| 58807 / 9808 | CMIN |
| 4134 | 163 |

---

## 八、常见问题

**Q：面板上看不到线路 / 重传数据？**
- 确认探针是**本分支编译的版本**（旧版没有这两个字段）
- 重传率**仅 Linux 探针可采集**（依赖 `/proc/net/snmp`）；macOS / Windows / FreeBSD 会自动降级，界面显示 `-`，不影响其他功能
- 线路识别需要探针能访问外网 CDN trace 端点；无外网或被墙时会显示「探针检测中」

**Q：一键命令装上去还是官方版？**
`raw.githubusercontent.com` 的**分支 URL 有 CDN 缓存**，刚更新后几分钟内可能仍返回旧脚本。等几分钟重试即可。校验时可改用提交 SHA 路径：`https://raw.githubusercontent.com/<owner>/<repo>/<commit-sha>/<file>`。

**Q：老探针会自己变成定制版吗？**
不会。老二进制的自动更新仍指向官方仓库，只会拉到官方版。需要重新执行一次安装命令，或手动替换二进制。

**Q：升级后数据会丢吗？**
不会。`--upgrade` 只替换二进制，不碰 `data` 目录。仍建议升级前备份 `/opt/komari/data`。

**Q：构建报 `sqlitetune ... conn.Exec undefined`？**
是**没有启用 CGO / 缺少 C 编译器**导致的，不是代码问题。安装 `build-essential`（或任意 gcc）后重新构建。

---

## 九、许可证

MIT，见 [LICENSE](./LICENSE) 与 [NOTICE](./NOTICE)。上游版权归 Komari Moniter 所有。
