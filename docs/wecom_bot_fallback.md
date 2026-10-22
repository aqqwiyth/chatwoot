# 微信客服 Bot 自动兜底与平台会话状态

微信客服收件箱配置页提供 Agent Bot 兜底设置。配置默认关闭，关联并启用收件箱 Agent Bot 后生效。

## 配置

现有收件箱创建/更新 API 的 `channel` 接受：

```json
{
  "bot_fallback_enabled": true,
  "bot_fallback_timeout_seconds": 30,
  "bot_fallback_target": "wecom_platform"
}
```

超时为 1～3600 的整数，目标只能是 `wecom_platform` 或 `chatwoot`。微信目标复用微信客服接待人员列表，有在线客服则接入，无在线客服则排队，每 3 分钟再次检查。Chatwoot 目标交回现有收件箱人工分配流程。

每条新的客户消息都会重置回复截止时间；重复投递、平台事件和客服消息不会重置。投递 HTTP/网络失败进入兜底，现有可重试错误在重试耗尽后处理。2xx 响应表示已接收；不解析其响应体为机器人回复。异步回复未成功发送给微信平台则仍可能超时。延迟任务受队列调度影响，配置秒数是最早触发时间。

## Bot 回复的轮次关联

**启用兜底前，应更新 Bot 集成，回传消息投递中的 token。** 每轮客户消息的 Bot webhook 会附带：

```json
{
  "wecom_bot_fallback": {
    "token": "current-delivery-token",
    "bot_id": 123
  }
}
```

Bot 使用现有消息创建 API 回复，在 `extensions` 中传回该消息的原始 token：

```json
{
  "content": "您好，以下是处理结果。",
  "message_type": "outgoing",
  "private": false,
  "extensions": {
    "wecom_bot_fallback_token": "current-delivery-token"
  }
}
```

文本或附件被微信发送接口成功接受后，仅解除对应 token 的等待。私有备注、命令、上传成功但发送失败不解除等待。旧 token 回复不会跨轮次发送。为兼容原有调用，缺少 token 的回复允许发送，但不能证明回复归属，因此不会解除自动兜底等待。人工成功回复可解除其创建前客户消息的等待。

转人工后停止该会话的 Bot 发送，仍可向 Bot 投递状态通知。会话重新进入 Bot 的 pending 接待并收到新的客户消息后，开始新轮次。已消费的异常/超时任务不再创建额外的排队轮询链。

## 平台会话状态

微信渠道的 Bot payload 附带 `platform_session`；它和 Chatwoot 原有 `status` 是两套状态：

```json
{
  "platform_session": {
    "provider": "wecom_customer_service",
    "channel_id": 1,
    "open_kfid": "wk...",
    "external_userid": "wm...",
    "service_state": 3,
    "servicer_userid": "zhangsan",
    "observed_at": "2026-10-22T10:00:00Z",
    "source": "event",
    "next_refresh_at": "2026-10-22T10:10:00Z",
    "stale": false
  }
}
```

状态数值：0 未处理、1 智能助手、2 人工排队、3 人工接待、4 已结束。首次未知为 `null`，不推断为 0；查询失败保留上次状态和观测时间，超过校准间隔时 `stale=true`。

平台事件先更新状态，再向 Bot 投递；有关联会话的微信原始事件使用 `wecom_sync_message`，附带 `raw_message` 和会话信息。无客户标识的事件仍保留原始数据，`platform_session=null`。

API 校准采用异步任务：调度器每分钟分批扫描，活跃且未结束的平台会话每 10 分钟查询一次。已结束状态或没有未结束 Chatwoot 会话时停止周期查询；新的客户消息可重新触发查询。查询失败下次在 10 分钟后尝试，已有状态不清空。较旧事件或查询开始之后已经收到更新状态时，不覆盖新状态。

## 部署与验收

先执行数据库迁移，再部署 Web/worker，并重启加载定时调度的 worker；前端需重新构建。已有渠道默认关闭兜底，按渠道配置并完成 token 回传后再开启。

建议用测试客服账号验证：投递失败、连续客户消息重新计时、正确 token 回复解除等待、旧 token 回复、无 token 回复、无人在线排队、两种目标、主动转人工、平台状态事件及 API 查询失败。不要用生产客户会话模拟转接故障。
