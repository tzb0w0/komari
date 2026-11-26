# Komari 定制版 · 部署与使用说明

基于 [Komari](https://github.com/komari-monitor/komari) 的定制分支。前台默认使用内置的 Glass 主题，后台管理走 `/admin` 原版界面；服务端与探针均使用本分支仓库发布的二进制。

- 前台：`https://<面板地址>/` — 服务器卡片、三网线路、整机重传率
- 后台：`https://<面板地址>/admin` — 节点、监控任务、设置等管理功能
- 面板里不再提供 WebSSH、主题市场、插件市场、远程执行入口

> 当前版本：服务端 **v0.3.3**、探针 **v0.2.4-fork**、内置 Glass 主题 `1.2.7-custom.13`。历史版本已清理，仓库只保留各自的最新版。

---

## 一、安装面板（服务端）

在**面板服务器**上以 root 执行：

```bash
curl -fsSL https://raw.githubusercontent.com/tzb0w0/komari/main/install.sh | bash
```

脚本行为：下载 `releases/latest` 的预编译二进制 → 安装为 systemd 服务 → 启动 → 打印访问地址。已安装时自动走升级流程（见第三节）。

| 默认值 | 内容 |
|---|---|
| 安装目录 | `/opt/komari` |
| 监听端口 | `25774` |
| 服务名 | `komari` |
| 下载版本 | `latest` |
| 依赖 | 仅 `curl` + `systemd`，不需要 go / node / gcc |

自动识别 `linux amd64` / `linux arm64`。

按需覆盖默认值：

```bash
curl -fsSL https://raw.githubusercontent.com/tzb0w0/komari/main/install.sh | bash -s -- --port 8080 --dir /www/komari
```

| 参数 | 说明 |
|---|---|
| `--port N` | 监听端口，默认 `25774` |
| `--dir PATH` | 安装目录，默认 `/opt/komari` |
| `--version TAG` | 指定版本标签，默认 `latest` |
| `--no-start` | 只替换二进制，不创建/重启服务 |

> ⚠️ 脚本会**重写 `/etc/systemd/system/komari.service`**，端口、目录、服务名固定为上面的默认值。当初安装时改过端口或目录，升级时必须带上同样的 `--port` / `--dir`，否则端口会被改回 `25774`，或装出第二套服务。执行前可用 `systemctl cat komari | grep ExecStart` 确认当前配置。

**备选：完整安装器（带管理菜单）**

需要 TUI 向导、卸载、清理升级备份等功能时使用，下载源同样指向本仓库：

```bash
curl -fsSLO https://raw.githubusercontent.com/tzb0w0/komari/main/install-komari.sh
sudo bash install-komari.sh
```

脚本从 `/dev/tty` 读取选项，务必用「先下载再运行」的形式，不要直接 `curl | bash`。

**Docker 部署**：一键脚本不适用，把镜像 tag 换成 `v0.3.3` 重新拉取即可。

---

## 二、首次启动与数据目录

首次访问 `http://<面板IP>:25774` 会进入安装引导，创建管理员账号。

> ⚠️ **数据目录跟随当前工作目录**：程序把数据写在 `./data`。必须在固定目录（如 `/opt/komari`）下启动；换目录启动会看到一个空数据库，看起来像「数据全丢了」，原数据其实还在旧目录。

一键脚本已自动写好 systemd 单元。手动部署时可参考：

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
```

`WorkingDirectory` 决定数据目录位置，**不要随意改动**。

---

## 三、升级

### 服务端

重跑同一条一键命令即可，无需卸载、无需编译环境：

```bash
curl -fsSL https://raw.githubusercontent.com/tzb0w0/komari/main/install.sh | bash
```

流程：备份旧二进制为 `komari.bak.<时间戳>` → 下载 `latest` 覆盖 → 重建服务并重启 → 打印回滚命令。`data/` 目录不受影响。自定义过安装位置时记得带 `--port` / `--dir`。

也可重跑 `install-komari.sh`，在管理菜单里选「升级」（稳定通道同样指向 `latest`）。源码自行编译的场景用 `build-from-source.sh --upgrade`，它会从 systemd 单元解析真实二进制路径、原子替换、启动失败自动回滚。

手动回滚：

```bash
sudo cp -p /opt/komari/komari.bak.<时间戳> /opt/komari/komari
sudo systemctl restart komari
```

> 服务端启动时会自动清空并重建 `./cache/dist`（内嵌的后台前端），Glass 主题按版本号覆盖 `data/theme/GlassCustom`。磁盘上不会残留旧前端，**唯一可能需要手动处理的是浏览器缓存**：升级后按 `Ctrl+Shift+R`，或清除站点数据（PWA Service Worker）。

### 探针

在后台「服务器 → 自动发现」重新复制一键命令，**在目标机器上重跑一次**即可。命令不锁版本号，脚本内部取 `latest`，会先停止旧服务、覆盖二进制、重建服务并启动；`auto-discovery.json` 保留，无需重新绑定。

> 重跑时请带上和原来一致的参数（如 `--get-ip-addr-from-nic`），否则 service 文件里的参数会丢失。若当初是用「手动运行二进制」方式部署的，则需自行替换文件并重启进程。

---

## 四、给被监控机器装探针

**推荐：面板生成命令（自动绑定）**

1. 后台 `/admin` → **设置** → 复制「自动发现密钥」（≥12 位，为空先设置）
2. 后台 → **服务器** → **自动发现** → 复制生成的命令
3. 粘贴到目标机器执行

执行后探针自动注册并绑定，凭据写在二进制同目录的 `auto-discovery.json`，无需手填 token。

**手动方式**

```bash
curl -fsSL https://raw.githubusercontent.com/tzb0w0/komari-agent/main/install.sh | bash -s -- \
  -e http://<面板IP>:25774 --auto-discovery "<自动发现密钥>"
```

也可在面板手动创建节点后用 token 方式：`-e http://<面板IP>:25774 -t "<TOKEN>"`。安装脚本的非 `--install*` 参数会原样传给探针二进制。

探针默认安装到 `/opt/komari/agent`，服务名 `komari-agent`。发布资产只有 `linux amd64` / `linux arm64` 两种。

---

## 五、前台卡片与数据说明

### 卡片布局

按**后台实际添加的监控任务数**动态分行，不强制三网：

- 左栏（延迟）：显示后台里那条监控任务的**名称** + 延迟进度条
- 右栏（丢包）：只显示探测到的**线路名** + 丢包进度条，不重复显示任务名
- 卡片右上角：**整机重传率** `重传 N%`；无数据时显示 `重传 未知`

左右两行按 `task_id` 一一对应。进度条按时间轴连续渲染，无采样时段用低调灰占位，不会断开。

### 三网线路

- 探测目标**完全来自后台填写的监控 IP**，按 `task_id` 对应到每一行，不是固定地址
- 用 `traceroute` / `mtr` 判回到国内三网走的是精品线路还是普通骨干，只显示产品级线路名（如 `CN2 GIA`、`9929`、`CMIN2`、`163`）；城域网节点和非产品级路径显示「未知」，不显示 ASN 供应商号
- 频率：**24 小时一次**；运行中只有监控目标真的变化才会额外探测，且有 90 秒去抖与 10 分钟最小间隔；逐条下发任务不会造成探测风暴
- **探针重启后必定重新检测一次**（这是预期行为），结果写入 `route-cache.json`，仅用于新进程首屏不空白
- 目标带端口（如 `:80`）时会自动改用 TCP traceroute

### 重传率

整机统计，读 `/proc/net/snmp` 的 `TcpRetransSegs / OutSegs`，**30 分钟窗口**，首次启动约 **5 分钟预热**后出数。ICMP 监控无法按目标 IP 拆分重传，因此这是整机值；非 Linux 系统无法采集，显示「未知」。

---

## 六、仓库与发布资产

| 仓库 | 角色 | 需要单独部署 |
|---|---|---|
| `tzb0w0/komari`（本仓库） | 服务端 Go，内嵌前台 Glass 主题与后台前端 | 是，1 台 |
| `tzb0w0/komari-web` | 后台前端源码（React / Vite），构建后嵌入服务端 | 否 |
| `tzb0w0/komari-agent` | 探针（Go） | 是，每台被监控机器 |

实际只需运行两个二进制：服务端 + 探针。

- 服务端发版时由 CI 从 `tzb0w0/komari-web` 构建后台前端，不再使用官方原版前端；后台的版本检查也指向 `tzb0w0/komari`
- 探针 `latest` 只发布 `komari-agent-linux-amd64` / `komari-agent-linux-arm64`；服务端 release 由工作流附带其他平台资产，可忽略
- 一键安装命令与面板复制的探针命令都取 `latest`，不锁定旧版本号

---

## 七、常见问题

**Q：升级后页面还是老样子？**
先 `Ctrl+Shift+R` 或清除站点数据。服务端每次启动都会重建 `./cache/dist`，磁盘残留不是原因，剩下基本都是浏览器 / PWA 缓存。

**Q：重传一直是「未知」？**
首次约 5 分钟预热，之后按 30 分钟窗口出数。确认探针是 Linux 且为本分支版本；非 Linux 不采集。

**Q：线路显示「未知」？**
确认后台那条监控 IP 可达、探针机上装了 `traceroute`（安装脚本会尽力安装）。城域网节点或非产品级路径按设计不标线路名。国际段与 ASN 供应商号不会当作回国线路显示。

**Q：某一行（如联通）丢包很高、延迟折线断断续续？**
这是该监控 IP 的真实 ICMP 丢包：探针单包超时即记为丢包，后端把没有延迟值的采样点转成空值，折线自然断续。线路判定只负责给名字，不参与丢包计算。先在探针机上 `ping -c 20 <该目标的IP>` 复现，再考虑换成对境外 ICMP 友好的目标 IP，或把该任务改为 TCP 探测。

**Q：跑完探针命令，后台没出现新服务器？**
查看目标机 `auto-discovery.json` 是否生成、`journalctl -u komari-agent -f` 是否连上面板；后台检查搜索框、分组筛选，以及是否与已有节点同 IP。命令里的 `-e` 地址要能被目标机访问。

**Q：升级后端口／目录变了？**
见第一节的警告，重跑时补上 `--port` / `--dir`。`--upgrade` 与数据目录无关，不会丢数据，但升级前备份 `/opt/komari/data` 是好习惯。

**Q：一键脚本拉到的是旧内容？**
`raw.githubusercontent.com` 的分支 URL 有 CDN 缓存，刚更新后几分钟内可能返回旧脚本，稍后重试；也可改用提交 SHA 路径 `https://raw.githubusercontent.com/<owner>/<repo>/<commit-sha>/<file>`。

**Q：从源码构建报 `sqlitetune ... conn.Exec undefined`？**
没有启用 CGO / 缺少 C 编译器。装好 `build-essential`（或任意 gcc）再构建，与代码无关。

---

## 八、许可证

MIT，见 [LICENSE](./LICENSE) 与 [NOTICE](./NOTICE)。上游版权归 Komari Monitor 所有。
