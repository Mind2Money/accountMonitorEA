# Account Monitor EA

一个用于 MetaTrader 5 的账户交易通知 EA。它监听账户交易事件，并通过 ServerChan（Server 酱）推送成交、挂单以及止盈止损变化通知。

> EA 只负责监听和推送通知，不会主动下单、平仓或修改订单。

## 功能

- 成交通知：监听真实 BUY / SELL 成交。
- 持仓止盈止损通知：监听持仓 SL / TP 添加或修改。
- 挂单通知：可选监听限价单、止损单、Stop Limit 等挂单创建。
- 挂单止盈止损通知：可选监听挂单 SL / TP 添加或修改。
- 支持 ServerChan Turbo 和 ServerChan 3 两种推送地址。
- 支持通过 EA 输入参数独立开关不同通知类型。

## 目录结构

```text
MQL5/
  accountMointorEA.mq5   # EA 源码
  accountMointorEA.ex5   # 已编译文件
```

## 安装

1. 打开 MT5，进入 `文件 -> 打开数据文件夹`。
2. 将 `MQL5/accountMointorEA.mq5` 复制到 MT5 数据目录下的 `MQL5/Experts/`。
3. 使用 MetaEditor 打开并编译，或直接使用仓库里的 `MQL5/accountMointorEA.ex5`。
4. 在 MT5 中刷新“导航器 -> 专家顾问”，把 EA 挂到任意图表。
5. 开启 MT5 的 Algo Trading / 自动交易。

## ServerChan 配置

在 MT5 中进入：

`工具 -> 选项 -> EA 交易`

勾选：

- `允许 WebRequest 用于列出的 URL`

然后按使用的模式添加 URL：

```text
https://sctapi.ftqq.com
```

如果使用 `sc3` 模式，还需要添加：

```text
https://<UID>.push.ft07.com
```

把 `<UID>` 替换为你的 ServerChan UID。

## 输入参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `InpServerChanMode` | `turbo` | 推送模式。支持 `turbo` 或 `sc3`。 |
| `InpSendKey` | `PUT_YOUR_SENDKEY_HERE` | ServerChan SendKey。不要把真实 SendKey 提交到公开仓库。 |
| `InpServerChanUID` | 空 | ServerChan 3 模式使用，`turbo` 模式无需填写。 |
| `InpNotifyDealAdd` | `true` | 成交通知开关。 |
| `InpNotifyPositionStopChange` | `true` | 持仓止盈止损添加或修改通知开关。 |
| `InpNotifyPendingOrderAdd` | `false` | 挂单创建通知开关。 |
| `InpNotifyOrderStopChange` | `false` | 挂单止盈止损添加或修改通知开关。 |
| `InpNotifyRequest` | `false` | 交易请求回报调试通知，通常无需开启。 |
| `InpHttpTimeoutMs` | `5000` | HTTP 请求超时时间，单位毫秒。 |

## 通知内容

通知标题会包含账户、品种和业务事件，例如：

```text
MT5成交通知 12345678 EURUSD BUY
MT5持仓止盈止损变化 12345678 XAUUSD
MT5挂单通知 12345678 GBPUSD BUY_LIMIT
```

通知正文包含：

- 账户、服务器、账户名称和时间。
- 交易事件类型、品种、订单号、成交号、持仓号。
- 订单类型、订单状态、手数、价格、SL、TP。
- 止盈止损变化时，会显示旧值和新值。

示例：

```text
SL: 未设置 -> 1.08350
TP: 1.09500 -> 1.09800
```

## 编译

推荐使用 MetaEditor 编译：

1. 打开 `MQL5/accountMointorEA.mq5`。
2. 点击 `编译`。
3. 确认没有 error。

也可以在 Windows 命令行中使用 MetaEditor：

```powershell
& "C:\Program Files\MetaTrader 5\MetaEditor64.exe" /compile:"E:\Documents\Repos\Trading\accountMointorEA\MQL5\accountMointorEA.mq5"
```

## 常见问题

### WebRequest failed

通常是 MT5 没有添加 ServerChan URL 白名单，或没有允许 WebRequest。检查：

- `工具 -> 选项 -> EA 交易 -> 允许 WebRequest 用于列出的 URL`
- 白名单是否包含当前使用模式的 ServerChan 域名。
- `InpSendKey` 是否填写正确。

### 没有收到通知

检查：

- EA 是否已经挂到图表。
- MT5 是否开启自动交易。
- 对应的通知开关是否为 `true`。
- ServerChan SendKey / UID 是否正确。
- MT5 日志中是否有 `ServerChan send failed` 或 `WebRequest failed`。

### 挂单相关通知没有推送

默认只开启成交和持仓 SL / TP 变化通知。挂单创建和挂单 SL / TP 变化需要手动开启：

```text
InpNotifyPendingOrderAdd = true
InpNotifyOrderStopChange = true
```

## 风险声明

本项目仅用于交易事件通知，不构成投资建议。请在模拟账户或低风险环境中充分测试后再用于真实账户。由于网络、平台、经纪商交易事件实现差异等原因，通知可能延迟、重复或遗漏。

## License

USE MIT LICENSE FOR ANY CASE. USE OR FORK THIS PROJECT MEANS YOU AGREED THIS STATEMENT.
