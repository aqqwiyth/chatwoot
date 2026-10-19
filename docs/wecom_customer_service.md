# 微信客服渠道

微信客服渠道用于接收微信客服消息，并把消息同时交给 Chatwoot 和下游机器人：

```text
微信客服
    │
    ▼
Chatwoot 回调接口
    │
    ├── 同步消息并创建 Chatwoot 联系人、会话和消息
    └── 转发到机器人 Webhook

Chatwoot 管理员回复
    │
    ▼
微信客服发送消息接口
```

管理员可以在 Chatwoot 中查看和回复消息，下游机器人也可以使用同一条消息做自动化处理。

> 术语说明：本渠道在产品界面中称为“微信客服”；“企业微信”用于企业微信群消息渠道。代码中的 `wecom_customer_service` 是兼容现有路由和数据表的技术标识，不代表产品显示名称。

## 渠道配置

在 Chatwoot 的收件箱配置中填写：

| 配置项 | 说明 |
| --- | --- |
| `open_kfid` | 要接入的微信客服账号 ID |
| 读取消息的 Secret | 用于获取微信客服 API access token |
| 企业 ID | 用于调用微信客服接口的 Corp ID |
| 回调 Token | 用于校验回调签名 |
| EncodingAESKey | 用于解密微信客服回调内容，必须是 43 位字符串 |
| 机器人 Webhook 地址 | Chatwoot 同步客户消息后发送的下游地址 |
| 欢迎语 | 用户进入会话事件的固定欢迎语，可选 |
| 接入会话话术 | 会话变更为接入客服（`change_type=1`）时的固定话术，可选 |
| 结束会话话术 | 会话变更为结束会话（`change_type=3`）时的固定话术，可选 |

收件箱创建后，Chatwoot 会生成回调地址：

```text
https://<chatwoot-domain>/webhooks/wecom_customer_service/<inbox-identifier>
```

在微信客服管理后台配置这个地址，并使用同一组 Token 和 EncodingAESKey 完成回调验证。

微信客服服务器无法访问 `localhost`。本地开发时需要使用公网 HTTPS 地址或内网穿透地址，例如：

```text
https://<public-domain>/webhooks/wecom_customer_service/<inbox-identifier>
```

## 回调处理

实现对应微信客服 API 文档：

- [接收消息回调](https://developer.work.weixin.qq.com/document/path/94669)
- [读取消息](https://developer.work.weixin.qq.com/document/path/94670)
- [发送消息](https://developer.work.weixin.qq.com/document/path/94677)
- [发送欢迎语等事件响应消息](https://developer.work.weixin.qq.com/document/path/95122)
- `kf/customer/batchget`：获取微信客服客户详情

### GET 验证

`GET /webhooks/wecom_customer_service/:identifier` 会：

1. 使用回调 Token 校验 `msg_signature`、`timestamp`、`nonce` 和 `echostr`。
2. 使用 EncodingAESKey 解密 `echostr`。
3. 返回解密后的明文。

直接在浏览器打开不带参数的回调地址会返回 `401`，这是预期行为。

### POST 回调

`POST /webhooks/wecom_customer_service/:identifier` 会：

1. 校验回调签名。
2. 解密 XML 或 JSON 内容。
3. 验证事件类型为 `kf_msg_or_event`。
4. 验证回调中的 `OpenKfId` 与收件箱配置一致。
5. 将回调中的同步 `Token` 和 `OpenKfId` 加入 Sidekiq 任务。
6. 立即返回 `success`。

`success` 只表示回调已经验签并进入异步处理，不表示微信客服消息已经同步成功或机器人已经收到消息。

## 消息同步和 Chatwoot 展示

Sidekiq 任务使用微信客服接口读取消息，并处理所有同步条目：

```text
origin = 3  客户消息，创建入站消息并转发
origin = 5  人工客服消息，创建出站消息并转发
origin = 4  系统事件，按事件是否带客户 ID 创建消息并转发
其他值     保留原文并转发
```

每条客户消息、人工客服消息和可关联客户的事件会：

1. 使用 `external_userid` 调用企业微信 `kf/customer/batchget`，从返回的 `customer_list` 获取联系人昵称和头像，然后查找或创建 Chatwoot 联系人。
2. 为当前收件箱创建或复用 Contact Inbox。
3. 创建一个未解决的 Conversation；如果原会话已经解决，则创建新会话。
4. 客户消息创建一条 Chatwoot 入站消息；`origin=5` 的人工客服消息创建一条 Chatwoot 出站消息，并在消息扩展中保存 `servicer_userid`。
5. 使用微信客服 `msgid` 做幂等判断，避免重复创建消息。
6. 更新微信客服同步游标。

每条同步条目都会向机器人 Webhook 增加 `origin`、`content` 和 `raw_message` 字段，同时保留原有 `msgtype=text` 和 `text.content` 格式。没有 `event.external_userid` 的事件不会创建 Chatwoot 会话，但会直接投递给收件箱 Agent Bot。

对于 `enter_session` 和 `session_status_change` 事件，配置的固定话术会立即通过 `kf/send_msg_on_event` 发送。Agent Bot 也可以创建私有文本命令触发同一接口：

```json
{
  "content": "欢迎语内容",
  "message_type": "outgoing",
  "content_type": "text",
  "private": true,
  "extensions": {
    "agent_bot_action": "wecom_event_response",
    "wecom_event_response": { "code": "WELCOME_CODE" }
  }
}
```

联系人会保存微信客服客户 ID，格式为：

```text
wecom:<corp_id>:<external_userid>
```

如果消息类型暂时没有对应的 Chatwoot 附件处理，消息正文会显示为类型占位文本，例如 `[图片消息]` 或 `[语音消息]`。

## 机器人 Webhook

客户消息写入 Chatwoot 后，还会发送到配置的 Webhook 地址。当前发送格式保持企业微信群机器人兼容格式；这里的下游机器人属于企业微信群机器人，当前渠道本身仍然是微信客服：

```json
{
  "msgtype": "text",
  "text": {
    "content": "[微信客服] 用户: wm_xxx | 客服账号: wk_xxx | 消息 ID: msg_xxx\n客户消息内容"
  },
  "event": "wecom_sync_message",
  "origin": 3,
  "content": "客户消息内容",
  "raw_message": { "msgid": "msg_xxx", "msgtype": "text" }
}
```

下游 Agent 可以根据消息正文中的用户 ID、客服账号 ID 和消息 ID 做自动化处理。Webhook 请求失败时，任务会失败并重试；消息已写入 Chatwoot，但只有在 Webhook 成功后才会标记为已转发。

## Agent Bot 转人工

Agent Bot 不直接调用企业微信 API，而是通过 Messages API 创建一条私有文本消息：

```json
{
  "content": "转人工",
  "message_type": "outgoing",
  "content_type": "text",
  "private": true,
  "extensions": {
    "agent_bot_action": "handoff"
  }
}
```

Chatwoot 异步读取该命令，使用微信客服凭证获取接待人员，并调用 `kf/service_state/trans`。有接待中的客服时转给指定人员；没有可用客服时转入待接入队列。转接状态和客服 ID 会写回消息扩展，私有命令不会发送给客户。

## Chatwoot 管理员回复

管理员在 Conversation 中发送回复后，Chatwoot 的 `SendReplyJob` 会调用微信客服发送消息接口：

```json
{
  "touser": "EXTERNAL_USERID",
  "open_kfid": "OPEN_KFID",
  "msgtype": "text",
  "text": {
    "content": "管理员回复内容"
  }
}
```

发送目标使用当前 Conversation 的 Contact Inbox `source_id`，即微信客服的 `external_userid`。

微信客服对消息发送有时间窗口、条数和客服账号 API 权限限制。如果微信客服 API 返回错误，Chatwoot 会查询当前会话状态，将原始错误和 `service_state` 写入消息失败原因，并在 Conversation 前端展示。只有 `service_state=0`（未处理）和 `1`（机器人接待中）可以通过 API 回复；`3` 表示当前由人工客服接待。

## 本地测试

将微信客服收到的 `postData` 原样保存为 `postData.xml`，并使用微信客服提供的签名参数：

```bash
CALLBACK_URL='http://localhost:3000/webhooks/wecom_customer_service/<inbox-identifier>'
MSG_SIGNATURE='<msgSignature>'
TIMESTAMP='<timeStamp>'
NONCE='<nonce>'

curl --noproxy localhost,127.0.0.1 -i -X POST \
  "${CALLBACK_URL}?msg_signature=${MSG_SIGNATURE}&timestamp=${TIMESTAMP}&nonce=${NONCE}" \
  -H 'Content-Type: text/xml; charset=utf-8' \
  --data-binary @postData.xml
```

预期回调响应：

```text
HTTP/1.1 200 OK

success
```

观察异步处理：

```bash
docker-compose -p chatwoot-preview \
  -f /tmp/chatwoot-preview-current.yml \
  logs -f rails sidekiq
```

完整链路需要同时确认：

1. Chatwoot 收件箱出现联系人、会话和客户消息。
2. 机器人 Webhook 收到转发内容。
3. 在 Chatwoot 回复后，微信客服客户收到回复。

## 常见问题

### 返回 `WeChat customer service does not match this channel`

检查解密后的 `OpenKfId` 是否和收件箱配置的 `open_kfid` 完全一致。URL 中的 `identifier` 与微信客服的 `OpenKfId` 不是同一个值。

### 回调返回 `success`，但 Chatwoot 没有消息

回调是异步处理的，先查看 Sidekiq 日志。检查 Rails 和 Sidekiq 容器是否可以解析并访问微信客服 API：

```bash
docker-compose -p chatwoot-preview \
  -f /tmp/chatwoot-preview-current.yml \
  exec sidekiq getent hosts qyapi.weixin.qq.com
```

如果容器返回 `bad address` 或 `getaddrinfo`，需要修复 Docker/Colima 的 DNS 配置和外网访问。修复后要重新发送回调，因为已经进入死信队列的任务不会自动恢复。

### Webhook 收不到消息

检查：

- Sidekiq 是否能访问机器人 Webhook 域名。
- Webhook 是否返回 HTTP 2xx。
- 下游是否按当前的 `msgtype=text` 格式接收请求。
- Sidekiq 日志中是否出现 `robot webhook returned HTTP` 错误。

### 旧消息没有出现在 Chatwoot

只有消息同步任务在本特性代码下成功执行后，才会创建 Chatwoot 消息。请重新发送一条客户消息或重新执行一次微信客服回调。
