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

只有已确认的微信平台状态 0、1 才允许普通消息 API 发送，并对 Bot 接待中的新客户消息启动回复等待。状态 2、3、4 以及未知状态仍向 Bot 投递，但不启动无响应计时，也不因该投递失败启动异常兜底。已有等待任务执行前重新检查当前状态，不能用旧 token 在不可回复状态下转人工。

转人工后停止该会话的 Bot 发送，仍可向 Bot 投递状态通知。会话重新进入 Bot 的 pending 接待并收到新客户消息，且已确认平台状态 0、1 时，开始新轮次。缓存仍为 4 或未知时异步查询，当前这次投递不要求回复；不能凭新客户消息直接推断状态为 0。已消费的异常/超时任务不再创建额外的排队轮询链；已发起的人工排队后续检查不受新等待规则影响。

`session_status_change.change_type=4` 表示重新接入已结束或已转接会话，映射为人工接待状态 3。专用事件提示接口与普通消息 API 的发送规则分别处理。

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

## 主动变更平台状态与本地同步

微信接口 `/cgi-bin/kf/service_state/trans` 调用成功，会按请求变更微信平台的会话状态或接待人员；本地是否立即同步，取决于调用入口。

| 调用入口 | 微信状态变更 | Chatwoot 本地状态同步 |
| --- | --- | --- |
| Bot 通过 Chatwoot 主动 handoff | 微信接口成功后变更 | HandoffService 在成功结果后立即写入平台状态快照 |
| Chatwoot 自动兜底转微信人工 | 微信接口成功后变更 | 同上，不等待平台回调或下一轮定时查询 |
| 外部 Bot 或其他系统直接调用微信 trans | 微信接口成功后变更 | 不会直接通知 Chatwoot；依靠实际收到的平台回调或后续符合条件的 API 校准 |

内部处理顺序为：查询当前平台状态 → 必要时调用 trans → 保存有效结果中的 `service_state` 和 `servicer_userid`，更新 `observed_at`，标记 `source=handoff` → 状态 2、3、4 时取消关联会话的 Bot 回复等待。接口失败时，不把期望目标状态写成成功状态。转接提示语发送失败单独记录，不回滚已经成功的状态同步。

平台快照按 `channel_id + external_userid` 保存在平台会话状态表中，供关联 Chatwoot 会话读取；后续消息和事件投递的 `platform_session` 使用该快照。这不等于直接覆盖 Chatwoot 的 `pending/open/resolved`，也不代表会话详情 API 或客服页面已经新增 `service_state` 字段或展示。

不能假定每一次外部 trans 都必然产生可用回调。未收到回调时，周期查询仅对仍有关联未结束 Chatwoot 会话、且本地平台状态不为 4 的记录执行，受扫描和队列调度影响，因此不能承诺外部调用后立即同步。新客户消息可重新触发查询。当前没有新增供外部系统调用的“状态已变更”回传 API；需要即时同步时，应通过现有 Chatwoot handoff 流程操作，或另行设计并实现成功回传入口。

## 部署与验收

先执行数据库迁移，再部署 Web/worker，并重启加载定时调度的 worker；前端需重新构建。已有渠道默认关闭兜底，按渠道配置并完成 token 回传后再开启。

建议用测试客服账号验证：投递失败、连续客户消息重新计时、正确 token 回复解除等待、旧 token 回复、无 token 回复、无人在线排队、两种目标、主动转人工、平台状态事件及 API 查询失败。不要用生产客户会话模拟转接故障。
