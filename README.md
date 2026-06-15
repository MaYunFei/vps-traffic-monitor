# VPS Traffic Monitor (VPS 流量监控与 Telegram 告警脚本)

这是一个轻量级、零外部依赖的 Linux VPS 流量监控及 Telegram 自动告警脚本。基于系统底层的流量统计工具 `vnstat`，并且支持自定义账单周期重置日、多档次阶梯报警，非常适合用于监控像 ZgoCloud、搬瓦工、DMIT 等有流量限制的 VPS。

## ✨ 特性

- 🚀 **纯 Shell 实现**: 极度轻量，无 Python 或 Node.js 等大型依赖，几乎不占用 CPU/内存资源。
- 🎯 **账单周期对齐**: 支持设置任意账单日（例如每月 22 号），完美契合 VPS 商家的结算周期。
- 🔔  **阶梯式防刷告警**: 流量耗尽达设定百分比后阶梯式警报（例如 80% $\rightarrow$ 90% $\rightarrow$ 95% $\rightarrow$ 100%），警报只在进入新阶段时发送一次，防止垃圾信息骚扰。
- ♻️ **自动重置与报告**: 每一个账单周期重置后，自动发送上一周期的流量消费总结，并清空告警状态。
- 🔌 **网卡自适应**: 自动识别系统默认公网网卡，无需手动麻烦配置。
- ⚙️ **配置与代码分离**: 配置全部存于 `config.env`，便于脚本升级和防信息泄露（方便开源保存）。

---

## 🛠 一键安装与部署

你只需要在你的 VPS 上运行以下一键安装命令：

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/MaYunFei/vps-traffic-monitor/main/install.sh)"
```

> **注**: 在执行脚本过程中，它会提示你：
> 1. 输入账单结算周期重置日（如 ZgoCloud 每月 `22` 号，则输入 `22`）。
> 2. 输入你的 Telegram Bot Token 和 Telegram Chat ID。
> 3. 自动将脚本写入 `cron` 定时任务（默认每 5 分钟执行一次检查）。

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
| `TELEGRAM_BOT_TOKEN` | - | 你的 Telegram Bot 访问 Token |
| `TELEGRAM_CHAT_ID` | - | 你的 Telegram 聊天 ID/群组 ID |
| `LIMIT_GB` | `1000` | 月度流量限制总额 (单位: GB) |
| `INTERFACE` | `""` | 指定网卡，留空代表自动检测主默认网卡 |
| `ALERT_THRESHOLD` | `80` | 起始报警阈值比例 (如已用 80% 时开始报警) |
| `DAILY_REPORT` | `true` | 是否启用每日流量例行报告总结 (`true`/`false`) |
| `DAILY_REPORT_HOUR` | `9` | 每日例行总结报告的发送时间整点 (0-23) |
| `STATE_DIR` | `/tmp` | 存储状态文件路径，防止重复报警 |
| `VPS_NAME` | `主机名` | 报警中显示的主机识别名，多台 VPS 时用于区分 |

---

## 🔍 命令手动测试与通道验证

在首次配完配置后，你可以手动调用绝对路径下的脚本触发一次 Telegram 推送通道测试：
```bash
/opt/vps-traffic-monitor/traffic_monitor.sh test
# 或者
/opt/vps-traffic-monitor/traffic_monitor.sh --test
```
如果配置无误，你的 Telegram 客户端会在数秒内收到一条带勾选图标的测试卡片。

你也可以静默试跑核心流量检测逻辑（只在超限时向 TG 推送告警）：
```bash
/opt/vps-traffic-monitor/traffic_monitor.sh
```

如果要强制查看 `vnstat` 服务当前统计的网卡流量：
```bash
vnstat
```

---

## 🗑 一键卸载

如果你需要完全清理和卸载监测工具，只需在 VPS 上以 `root` 用户运行以下卸载命令：

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/MaYunFei/vps-traffic-monitor/main/uninstall.sh)"
```

> **注**：卸载程序将自动：
> 1. 清理 Cron 时钟检测任务。
> 2. 将 `/etc/vnstat.conf` 中的账单结算日重置回默认的每月 1 号。
> 3. 清理并彻底删除安装所在绝对目录 `/opt/vps-traffic-monitor/`。

---

## 🛠️ 重新配置或更新参数

你随时可以再次运行一键安装配置命令来修改配置（例如变更流量额度、阈值或重设 TG Bot）：

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/MaYunFei/vps-traffic-monitor/main/install.sh)"
```

当检测到系统已存在原配置文件时，脚本会安全地向你确认：
- **`Do you want to reconfigure it? [y/N]`**
  - **输入 `y`**：你可以重新交互输入所有参数并覆盖更新。
  - **直接回车或输入 `n`**：不变更历史参数配置，仅修复被改动或丢失的脚本及定时任务文件。

---

## 📋 常见问题与排错

### 1. 为什么手动执行时提示 `vnstat: command not found`？
- 本脚本安装器会自动尝试给你安装 `vnstat`。如果自动安装失败，可按照你系统类型手动安装：
  - **Ubuntu/Debian**: `apt-get install -y vnstat jq bc curl`
  - **CentOS/Rocky**: `yum install -y epel-release && yum install -y vnstat jq bc curl`

### 2. 新安装的 vnstat 为什么不跑流量？
- `vnstat` 在系统刚安装后的 **前几个小时** 默认可能尚未建立足够的日报表和月报表（需要等它守护进程收集一些数据）。因此脚本第一次跑显示 `Warning: vnstat monthly stats not ready yet` 是正常的，流量跑一阵子就好了。

---

## 📄 LICENSE

[MIT License](LICENSE)
