# VPS Traffic Monitor & Telegram Alerts (VPS 流量监控与 Telegram 告警脚本)

[English](#english) | [简体中文](#简体中文)

---

# English

A lightweight, zero-dependency Linux VPS traffic monitoring and Telegram alert script. Based on the system-level traffic statistics tool `vnstat`, it supports custom billing cycle reset days, multi-level alert thresholds, and on-demand active status queries. Perfect for configuration-limited VPS providers (e.g., ZgoCloud, BandwagonHost, DMIT, etc.).

## ✨ Features

- 🚀 **Pure Shell Implementation**: Extremely lightweight, no Python/Node.js dependencies, virtually zero CPU/RAM footprint.
- 🎯 **Billing Period Alignment**: Custom billing day reset option (e.g., reset on the 22nd), matching billing cycles exactly.
- 🔔  **Multi-Level Alerts**: Anti-spam alerts that trigger once at each tier (e.g., 80% $\rightarrow$ 90% $\rightarrow$ 95% $\rightarrow$ 100%), preventing notification flood.
- ♻️ **Auto Reset & Report**: Emits a traffic metric summary from the previous cycle once it resets, clearing alert history state.
- 🔌 **Auto Interface Detection**: Automatically identifies default public interfaces without manual settings.
- 🔍 **Active Bot Commands (Optional)**: A systemd-managed polling daemon allowing you to send `/traffic` or `/status` to query usage dynamically.
- ⚙️ **Config & Code Separation**: All custom variables reside in `config.env` for security and clean updates.

---

## 🛠 Easy Installation

Simply execute the following command as `root` on your Linux VPS:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/MaYunFei/vps-traffic-monitor/main/install.sh)"
```

- During installation, you will be prompted to select your language (`English` or `简体中文`).
- You can configure the monthly limit, alert threshold, billing reset day, daily scheduled reports, and whether to enable the active `/traffic` Command Listener Service.

---

## ⏰ Timing Interval & Security Notice

For safety against burst bandwidth usage (e.g. DDoS, loop bugs), the cron task inspects traffic data **every 5 minutes**.

- **Why cron instead of a heavy resident daemon?**
  Cron execution is optimized. The script reads vnstat metrics in JSON dynamically, taking only milliseconds.
- **What is the 5-minute safety threshold margin?**
  At 1 Gbps max throughput, the VPS transfers at most **37.5 GB** in 5 minutes. If quota warning thresholds are set to `80%` or `90%`, it leaves a safe gap for you to take controls before limits are exceeded.

---

## ⚙️ Configuration Properties (`config.env`)

You can directly manage your settings via:
```bash
nano /opt/vps-traffic-monitor/config.env
```

| Config Key | Default | Description |
| :--- | :--- | :--- |
| `MONITOR_LANG` | `en` | Bot card language and output messages (`en` / `zh`). |
| `TELEGRAM_BOT_TOKEN` | - | Access Token for your Telegram Bot |
| `TELEGRAM_CHAT_ID` | - | Chat ID or Group ID to push alerts/receive query commands |
| `LIMIT_GB` | `1000` | Monthly traffic quota limit in GB |
| `INTERFACE` | `""` | Dedicated interface to monitor (auto-detects default if empty) |
| `ALERT_THRESHOLD` | `80` | Starting alert percentage threshold |
| `DAILY_REPORT` | `true` | Daily scheduled traffic usage reports (`true`/`false`) |
| `DAILY_REPORT_HOUR` | `9` | Hour of the day to send daily reports (0-23) |
| `STATE_DIR` | `/tmp` | State tracking directory preventing spam alerts |
| `VPS_NAME` | `hostname` | Host display identifier shown in alert notifications |

---

## 🔍 Manual Testing & Command Query

Send a test visual card notification to verify Telegram paths:
```bash
/opt/vps-traffic-monitor/traffic_monitor.sh test
```

Perform automated query and echo/send output card payload:
```bash
/opt/vps-traffic-monitor/traffic_monitor.sh query [chat_id]
```

Retrieve basic local system network traffic stats via native CLI:
```bash
vnstat
```

⚠️ **Important Notice for Multi-VPS Setup**: 
Telegram strictly prohibits running multiple polling connections (`getUpdates` - the active command listener) on a single Bot Token simultaneously. If you have multiple VPS instances using the **same Bot Token**, they will conflict (causing 409 errors), and `/traffic` commands will only be answered by one of them at random. 
**Best Practices**:
1. Assign a unique Telegram Bot (individual Token) for each VPS.
2. Alternatively, only enable the active query listener daemon on **one** of your VPS servers, and leave others running in push-only mode (choose `n` for listener service onboarding during installation). Single-direction push notifications from multiple servers using the same Bot Token will work completely fine and do not conflict.

---

## 📊 Telegram Message Previews

Below are the styles of notifications sent by the Telegram Bot for various events:

#### 1. Real-time Traffic Status Card (also used for `test`)
```text
📊 VPS Real-time Traffic Status (My-Dallas-VPS)
━━━━━━━━━━━━━━━━━━
• Interface: eth0
• Today Download (RX): 3.80 GB
• Today Upload (TX): 1.40 GB
• Today Total Used: *5.20 GB* 📅
• Month Total Used: *165.57 GB* (of 1000 GB)
• Usage Ratio: *16%*
• Billing Cycle: Monthly day 22
```

#### 2. Usage Alert Warning Card
```text
⚠️ VPS Traffic Alert (My-Dallas-VPS)
━━━━━━━━━━━━━━━━━━
• Interface: eth0
• Download (RX): 610.15 GB
• Upload (TX): 192.40 GB
• Total Used: 802.55 GB
• Quota: 1000 GB
• Usage Ratio: 80%
• Threshold: 80% 📈
• Billing Cycle: Monthly day 22

Traffic consumption has reached the threshold. Adjust usage accordingly.
```

#### 3. Monthly Cycle Reset Notification
```text
✅ VPS Traffic Reset (My-Dallas-VPS)
━━━━━━━━━━━━━━━━━━
• Interface: eth0
• New Term Used: 0.12 GB
• Usage Ratio: 0%
• Billing Cycle: Reset on monthly day 22 ♻️
```

#### 4. Scheduled Daily Usage Report
```text
📊 VPS Daily Traffic Report (My-Dallas-VPS)
━━━━━━━━━━━━━━━━━━
• Interface: eth0
• Today Download (RX): 4.15 GB
• Today Upload (TX): 1.05 GB
• Today Total Used: *5.20 GB* 📅
• Month Total Used: *427.92 GB* (of 1000 GB)
• Month Remaining: 572.08 GB
• Usage Ratio: *42%*
• Billing Cycle: Monthly day 22

Status is good, monitoring active...
```

---

## 🗑 One-Click Uninstall

To clean files, cron configurations, and systemd services, it is highly recommended to run the local uninstaller script as `root`:

```bash
sudo /bin/bash /opt/vps-traffic-monitor/uninstall.sh
```

Alternatively, you can run the remote oneclick uninstall command:
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/MaYunFei/vps-traffic-monitor/main/uninstall.sh)"
```

Uninstall will automatically:
1. Delete monitoring cron files.
2. Disable and delete the systemd Telegram command listener service.
3. Reset `/etc/vnstat.conf` MonthRotate back to the default (1st).
4. Remove the installation directory `/opt/vps-traffic-monitor/`.

---

# 简体中文

这是一个轻量级、零外部依赖的 Linux VPS 流量监控及 Telegram 自动告警与状态查询脚本。基于系统底层的流量统计工具 `vnstat`，并且支持自定义账单周期重置日、多档次阶梯报警，非常适合用于监控像 ZgoCloud、搬瓦工、DMIT 等有流量限制的 VPS。

## ✨ 特性

- 🚀 **纯 Shell 实现**: 极度轻量，无 Python 或 Node.js 等大型依赖，几乎不占用 CPU/内存资源。
- 🎯 **账单周期对齐**: 支持设置任意账单日（例如每月 22 号），完美契合 VPS 商家的结算周期。
- 🔔  **阶梯式防刷告警**: 流量耗尽达设定百分比后阶梯式警报（例如 80% $\rightarrow$ 90% $\rightarrow$ 95% $\rightarrow$ 100%），警报只在进入新阶段时发送一次，防止垃圾信息骚扰。
- ♻️ **自动重置与报告**: 每一个账单周期重置后，自动发送上一周期的流量消费总结，并清空告警状态。
- 🔌 **网卡自适应**: 自动识别系统默认公网网卡，无需手动麻烦配置。
- 🔍 **Telegram 指令主动查询 (可选)**: 极轻量长轮询后台服务，允许通过给机器人发送 `/traffic` 或 `/status` 实时调取数据卡片。
- ⚙️ **配置与代码分离**: 配置全部存于 `config.env`，便于脚本升级和防信息泄露（方便开源保存）。

---

## 🛠 一键安装与部署

你只需要在你的 VPS 上运行以下一键安装命令：

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/MaYunFei/vps-traffic-monitor/main/install.sh)"
```

- 安装中，首先选择系统安装语言偏好 (`1. English` 或 `2. 简体中文`)。
- 随后您可以交互式配置流量重置日、月度流量总额、警报比例、每日例行汇报机制，以及配置并开启 `/traffic` Telegram 主动查询监听守护服务。

---

## ⏰ 定时检查机制与安全性说明

为了防范突发的高带宽异常跑数跑飞（如遭受 DDoS 攻击、爬虫死循环等风险），本脚本默认被配置为 **每 5 分钟执行一次** 底层流量轮询。

- **为什么不用秒级或常驻挂载守护？**
  `cron` 定时唤醒是 Linux 系统对性能损耗最小的做法。由于本脚本纯粹通过 `jq` 与 `bc` 快速读取本地 `vnstat` 的持久化 JSON，每次调用瞬间仅消耗几毫秒，即便 5 分钟唤醒一次也是 **CPU 及内存零开销**。
- **5 分钟的安全边界是多少？**
  以主流 1 Gbps 满载跑满为例，在最坏情况下的 5 分钟轮询延迟最大会走掉约 **37.5 GB** 的流量。在设置 `600G` 大小的额度下，如果将警报线设置为 `80%` 或者 `90%`，5分钟的间隔有着极充足的安全缓冲垫层，足够在耗尽前让你收到提醒并及时上去控制。

---

## ⚙️ 配置文件说明 (`config.env`)

若要修改配置，请直接编辑绝对路径下的配置文件：
```bash
nano /opt/vps-traffic-monitor/config.env
```

| 配置项 | 默认值 | 说明 |
| :--- | :--- | :--- |
| `MONITOR_LANG` | `en` | 发送卡片和交互提示使用的语言 (`en` / `zh`) |
| `TELEGRAM_BOT_TOKEN` | - | 你的 Telegram Bot 访问 Token |
| `TELEGRAM_CHAT_ID` | - | 你的 Telegram 聊天 ID/群组 ID，用于接收推送和响应指令 |
| `LIMIT_GB` | `1000` | 月度流量限制总额 (单位: GB) |
| `INTERFACE` | `""` | 指定网卡，留空代表自动检测主默认网卡 |
| `ALERT_THRESHOLD` | `80` | 起始报警阈值比例 (如已用 80% 时开始报警) |
| `DAILY_REPORT` | `true` | 是否启用每日流量例行报告总结 (`true`/`false`) |
| `DAILY_REPORT_HOUR` | `9` | 每日例行总结报告的发送时间整点 (0-23) |
| `STATE_DIR` | `/tmp` | 存储状态文件路径，防止重复报警 |
| `VPS_NAME` | `主机名` | 报警中显示的主机识别名，多台 VPS 时用于区分 |

---

## 🔍 命令手动测试与通道验证

手动调用脚本触发送一次 Telegram 推送通道测试：
```bash
/opt/vps-traffic-monitor/traffic_monitor.sh test
```

手动触发一次当前状态卡片渲染返回：
```bash
/opt/vps-traffic-monitor/traffic_monitor.sh query [chat_id]
```

强制查看 `vnstat` 服务当前统计的网卡流量：
```bash
vnstat
```

⚠️ **多 VPS 共用 Bot 时的冲突警告**: 
Telegram 协议限制同一个 Bot Token 在同一时刻只能由一个长轮询连接（`getUpdates`，即后台监听服务）接管。如果您有多个 VPS 配置了**同一个** Bot Token 并同时开启了主动查询监听，监听程序会互相争抢消息更新队列（导致 409 连接冲突），使得最终只有一个 VPS 不定时地回复查询。
**最佳实践建议**：
1. **推荐做法**：为每个 VPS 申请**独立的 Telegram Bot Token**，使用不同的机器人分别查询。
2. **共用 Token 做法**：仅在其中**一台**核心 VPS 上开启主动查询监听脚本，其他 VPS 一键安装时不启用主动查询监听（在一键安装选择主动监听服务时输入 `n` 即可）。多台 VPS 定时推送/阈值警报发消息到同一个 Token/会话是完全支持的，不会产生任何冲突。

---

## 📊 Telegram 消息卡片预览

以下是各类通知事件触发时，Telegram 机器人发送的信息卡片格式预览：

#### 1. 实时流量状态卡片（测试推送也使用此样式）
```text
📊 VPS 流量实时状态 (My-Dallas-VPS)
━━━━━━━━━━━━━━━━━━
• 监控网卡: eth0
• 今日下载 (RX): 3.80 GB
• 今日上传 (TX): 1.40 GB
• 今日合计已用: *5.20 GB* 📅
• 本月已用 (累计): *165.57 GB* (共 1000 GB)
• 使用比例: *16%*
• 计算周期: 每月 22 号重置
```

#### 2. 超限警报卡片
```text
⚠️ VPS 流量告警通知 (My-Dallas-VPS)
━━━━━━━━━━━━━━━━━━
• 网卡名称: eth0
• 下载流量 (RX): 610.15 GB
• 上传流量 (TX): 192.40 GB
• 合计已用: *802.55 GB*
• 流量配额: 1000 GB
• 消耗比例: *80%*
• 警告阈值: 80% 📈
• 账单重置: 每月 22 号

流量消耗已达到设定等级，请及时调整使用策略。
```

#### 3. 月度周期流量重置卡片
```text
✅ VPS 流量重置通知 (My-Dallas-VPS)
━━━━━━━━━━━━━━━━━━
• 网卡名称: eth0
• 新周期已用: 0.12 GB
• 使用比例: 0%
• 账单重置: 已于每月 22 号完成重置 ♻️
```

#### 4. 每日例行流量报告卡片
```text
📊 VPS 每日流量汇报 (My-Dallas-VPS)
━━━━━━━━━━━━━━━━━━
• 监控网卡: eth0
• 今日下载 (RX): 4.15 GB
• 今日上传 (TX): 1.05 GB
• 今日合计已用: *5.20 GB* 📅
• 本月已用 (累计): *427.92 GB* (共 1000 GB)
• 本月剩余流量: 572.08 GB
• 使用比例: *42%*
• 计算周期: 每月 22 号重置

状态良好，监控运行中...
```

---

## 🗑 一键卸载

如果你需要完全清理和卸载监测工具，建议直接运行本地卸载脚本：

```bash
sudo /bin/bash /opt/vps-traffic-monitor/uninstall.sh
```

或者在 VPS 上以 `root` 用户运行以下远程卸载命令：

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/MaYunFei/vps-traffic-monitor/main/uninstall.sh)"
```

卸载程序将自动：
1. 清理 Cron 时钟检测任务。
2. 关闭、停用并清理 Telegram 后台监听服务系统单元。
3. 将 `/etc/vnstat.conf` 中的账单结算日重置回默认的每月 1号。
4. 清理并彻底删除安装所在绝对目录 `/opt/vps-traffic-monitor/`。

---

## 📄 LICENSE

[MIT License](LICENSE)
