# Group Messaging v4.17.1 变更与本地发布说明

## 1. 基线与目录

- Chatwoot 基线：`v4.17.1`
- 开发分支：`codex-group-messaging-v4.17.1`
- Worktree：`/Users/ouzhouyou/dev/chatwoot/.worktrees/group-messaging-v4.17.1`
- 开发镜像：`chatwoot-preview:group-messaging-dev`
- 生产预览镜像：`chatwoot-preview:group-messaging-v4.17.1`
- 本地入口：`http://localhost:3000`
- Vite：`http://localhost:3036/vite-dev/`

所有构建、测试和发布命令都应在上述 worktree 中执行。

## 2. 本次功能变更

### 2.1 Group Messaging Channel

新增统一群聊渠道：

```text
Channel::GroupMessaging
GroupMessaging::Providers::Wecom
GroupMessaging::Providers::Feishu
GroupMessaging::Providers::Dingtalk
```

`channel_group_messaging` 保存：

- `provider`：`wecom`、`feishu` 或 `dingtalk`
- `identifier`：渠道实例的稳定标识
- `provider_config`：Webhook、发送地址、访问令牌、过滤与路由配置
- `capabilities`：引用、@成员、线程等能力声明

当前 provider adapter 共用 canonical payload、HMAC 验证和通用 `send_url` 投递协议。企业微信、飞书、钉钉官方事件验签和官方发送 API 仍需在对应 adapter 中继续实现。

### 2.2 CRM 边界

- 一个外部群对应一个群 Contact、ContactInbox 和 Conversation。
- 群 Contact 使用 `contact_type: group`，继续支持现有标签、备注、自定义属性、搜索和自动化能力。
- provider 数据保存在 `contacts.extensions`，业务 CRM 数据继续保存在 `custom_attributes`。
- 群成员暂不创建独立 Contact；消息通过 `extensions.actor` 保存发言人身份快照。
- `actor.identity_key` 默认为 `provider:external_id`，作为后续成员级 CRM 的迁移锚点。

### 2.3 数据库变更

迁移文件：

```text
db/migrate/20260905000000_add_group_messaging_extensions.rb
db/migrate/20260906000000_reconcile_contact_type_for_chatwoot_v417.rb
```

新增：

- `channel_group_messaging` 表
- `contacts.extensions: jsonb`
- `conversations.extensions: jsonb`
- `messages.extensions: jsonb`
- `messages.external_event_id: string`
- 消息幂等唯一索引：`inbox_id + external_event_id`

兼容迁移将旧版字符串 `contacts.contact_type` 转换为 v4.17.1 的整数枚举，并保留 `group` 类型。

### 2.4 入站消息

Webhook 路径：

```text
POST /webhooks/group_messaging/:provider/:identifier
```

流程：

```text
Webhook
  -> provider adapter 验证
  -> EventNormalizer
  -> inbox_id + external_event_id 幂等检查
  -> 创建或查找群 Contact/ContactInbox
  -> 创建或查找 Conversation
  -> 保存 Message 和 actor 快照
  -> Chatwoot 消息事件
```

canonical 入站示例：

```json
{
  "group_id": "oc_mock_group",
  "external_event_id": "evt_mock_001",
  "external_message_id": "om_mock_001",
  "content": "这是一条群聊测试消息",
  "content_type": "text",
  "kind": "text",
  "group": {
    "external_id": "oc_mock_group",
    "display_name": "研发测试群",
    "avatar_url": "https://example.test/group.png",
    "member_count": 3
  },
  "actor": {
    "external_id": "ou_mock_member",
    "display_name": "测试成员",
    "avatar_url": "https://example.test/member.png",
    "role": "member",
    "is_bot": false
  },
  "provider": {
    "event_id": "evt_mock_001",
    "message_id": "om_mock_001",
    "thread_id": "omt_mock_001"
  }
}
```

如果配置了 `provider_config.webhook_secret`，请求需要携带：

```text
X-Group-Signature: sha256=<raw body 的 HMAC-SHA256>
```

### 2.5 出站消息

坐席回复通过 `GroupMessaging::OutboundMessageService` 和对应 provider adapter 投递。

当前通用 adapter 使用：

```text
provider_config.send_url
provider_config.access_token
```

向发送地址提交群 ID、消息内容、内容类型和 `extensions`。成功响应需返回 `message_id` 或 `id`，并写入 Chatwoot `message.source_id`。

### 2.6 前端

新增内置消息渲染注册表：

```text
app/javascript/dashboard/channels/messageRendererRegistry.js
```

解析顺序：

```text
provider + message kind
-> provider + *
-> channel + message kind
-> channel + *
-> 通用消息渲染
```

已增加 Group Messaging Inbox 创建与配置界面，并在消息区域读取 `extensions.actor` 展示群成员身份。

### 2.7 Provider 创建与编辑体验

群聊创建页已改为 Provider 卡片式选择，当前仅启用“企业微信（会话存档）”；企业微信 RPA、飞书群和钉钉群显示为置灰的未实现项。

企业微信表单支持以下配置：

- `company_name`、`company_id`
- `allowed_group_owners`、`allowed_group_ids`、`ignored_group_ids`
- `routing_rules`：按群主或群 ID 将会话分配到指定团队
- `send_account_id`、`send_base_url`、`webhook_secret`

编辑 Inbox 时，配置页提供完整 `provider_config` JSON 的查看、编辑和保存，并对 JSON 格式和后端错误进行提示。

入站处理会先应用群过滤规则，再创建会话；命中 `routing_rules` 且团队属于当前账号时，自动设置会话团队。`send_url` 与 `send_base_url` 均可作为出站地址。

Inbox 列表已补充 `Channel::GroupMessaging` 的中英文显示名称，避免出现 `INBOX_MGMT.CHANNELS.undefined`。

当前前端创建入口在 `/settings/inboxes/new` 中直接展示“企业微信”渠道卡片：

```text
key: group_messaging
provider: wecom
```

`ChannelItem` 已将 `group_messaging` 视为可用渠道，不依赖账号 feature 列表加载完成，因此不会因 feature 配置尚未返回而显示为灰色。后端仍使用独立的 `Channel::GroupMessaging` 模型，Inbox 的 `channel_type` 为 `Channel::GroupMessaging`。

`Channel::GroupMessaging` 目前还提供：

- provider 作用域内唯一的 `identifier`
- 企业微信 `company_name`、`company_id`、`send_base_url`、`send_account_id` 必填校验
- provider 名称显示：企业微信、飞书、钉钉

## 3. 当前本地开发运行方式

开发环境使用源码 volume 挂载，不需要为每次代码修改重新构建 Docker 镜像：

```text
/tmp/chatwoot-preview-compose.yml
/tmp/chatwoot-preview-dev.override.yml
```

当前服务：

```text
rails    chatwoot-preview:group-messaging-dev  3000
sidekiq  chatwoot-preview:group-messaging-dev
vite     chatwoot-preview:group-messaging-dev  3036
postgres 原 chatwoot-preview 数据库
redis    原 chatwoot-preview Redis
```

Vite 已允许 Rails 容器以 `vite` 服务名代理资源；`/vite-dev/@vite/client` 应返回 HTTP 200。

## 4. 修改代码后如何生效

### 4.1 前端代码

修改 Vue、JavaScript、HTML 或 CSS 后，Vite 自动热更新，通常不需要执行命令。

修改 `vite.config.ts` 或 `config/vite.json` 后重启 Vite：

```bash
DOCKER_CONFIG=/tmp/chatwoot-docker-config \
DOCKER_HOST=unix:///Users/ouzhouyou/.colima/default/docker.sock \
docker-compose -p chatwoot-preview \
  -f /tmp/chatwoot-preview-compose.yml \
  -f /tmp/chatwoot-preview-dev.override.yml \
  restart vite
```

### 4.2 Rails 后端代码

Controller、Model 和 Service 在 development 环境中按请求重新加载，通常只需重新请求接口。

修改 initializer、环境配置或需要常驻进程重新加载的内容时：

```bash
DOCKER_CONFIG=/tmp/chatwoot-docker-config \
DOCKER_HOST=unix:///Users/ouzhouyou/.colima/default/docker.sock \
docker-compose -p chatwoot-preview \
  -f /tmp/chatwoot-preview-compose.yml \
  -f /tmp/chatwoot-preview-dev.override.yml \
  restart rails
```

修改 Job 或 Sidekiq 使用的代码后建议重启 Sidekiq：

```bash
DOCKER_CONFIG=/tmp/chatwoot-docker-config \
DOCKER_HOST=unix:///Users/ouzhouyou/.colima/default/docker.sock \
docker-compose -p chatwoot-preview \
  -f /tmp/chatwoot-preview-compose.yml \
  -f /tmp/chatwoot-preview-dev.override.yml \
  restart sidekiq
```

### 4.3 数据库迁移

```bash
DOCKER_CONFIG=/tmp/chatwoot-docker-config \
DOCKER_HOST=unix:///Users/ouzhouyou/.colima/default/docker.sock \
docker-compose -p chatwoot-preview \
  -f /tmp/chatwoot-preview-compose.yml \
  -f /tmp/chatwoot-preview-dev.override.yml \
  exec rails bundle exec rails db:migrate
```

查看迁移状态：

```bash
DOCKER_CONFIG=/tmp/chatwoot-docker-config \
DOCKER_HOST=unix:///Users/ouzhouyou/.colima/default/docker.sock \
docker-compose -p chatwoot-preview \
  -f /tmp/chatwoot-preview-compose.yml \
  -f /tmp/chatwoot-preview-dev.override.yml \
  exec rails bundle exec rails db:migrate:status
```

### 4.4 Gem 或 pnpm 依赖变化

修改以下文件时需要重建开发镜像：

```text
Gemfile
Gemfile.lock
package.json
pnpm-lock.yaml
docker/Dockerfile
```

```bash
cd /Users/ouzhouyou/dev/chatwoot/.worktrees/group-messaging-v4.17.1

DOCKER_CONFIG=/tmp/chatwoot-docker-config \
DOCKER_HOST=unix:///Users/ouzhouyou/.colima/default/docker.sock \
docker build --progress=plain \
  -f docker/Dockerfile \
  -t chatwoot-preview:group-messaging-dev \
  --build-arg BUNDLE_WITHOUT='' \
  --build-arg EXECJS_RUNTIME=Node \
  --build-arg RAILS_ENV=development \
  --build-arg RAILS_SERVE_STATIC_FILES=false \
  .

DOCKER_CONFIG=/tmp/chatwoot-docker-config \
DOCKER_HOST=unix:///Users/ouzhouyou/.colima/default/docker.sock \
docker-compose -p chatwoot-preview \
  -f /tmp/chatwoot-preview-compose.yml \
  -f /tmp/chatwoot-preview-dev.override.yml \
  up -d --force-recreate rails sidekiq vite
```

## 5. 构建和发布生产预览镜像

生产镜像会执行完整前端资源编译，因此比开发模式慢。不要使用代码监听脚本做日常前端开发，只在需要生成可部署镜像时构建一次。

### 5.1 构建镜像

```bash
cd /Users/ouzhouyou/dev/chatwoot/.worktrees/group-messaging-v4.17.1

DOCKER_CONFIG=/tmp/chatwoot-docker-config \
DOCKER_HOST=unix:///Users/ouzhouyou/.colima/default/docker.sock \
docker build --progress=plain \
  -f docker/Dockerfile \
  -t chatwoot-preview:group-messaging-v4.17.1 \
  .
```

也可以执行：

```bash
make build_group_messaging_image
```

`script/watch_group_messaging_image.sh --once` 会优先使用 `docker buildx build --load`；检测不到 buildx 时回退到兼容 legacy builder 的 `docker build`，避免旧版 Docker 因不支持 `--progress` 参数构建失败。

### 5.2 发布前迁移数据库

```bash
DOCKER_CONFIG=/tmp/chatwoot-docker-config \
DOCKER_HOST=unix:///Users/ouzhouyou/.colima/default/docker.sock \
docker-compose -p chatwoot-preview \
  -f /tmp/chatwoot-preview-compose.yml \
  -f /tmp/chatwoot-preview-local.override.yml \
  run --rm --no-deps rails bundle exec rails db:migrate
```

数据库升级前应先保留备份。不要执行 `down -v`，否则会删除数据库和 Redis volume。

### 5.3 替换生产 Rails 和 Sidekiq

```bash
DOCKER_CONFIG=/tmp/chatwoot-docker-config \
DOCKER_HOST=unix:///Users/ouzhouyou/.colima/default/docker.sock \
docker-compose -p chatwoot-preview \
  -f /tmp/chatwoot-preview-compose.yml \
  -f /tmp/chatwoot-preview-local.override.yml \
  up -d --no-build --force-recreate rails sidekiq
```

生产模式不需要启动 Vite 服务，前端资源已经包含在镜像中。

### 5.4 验证

```bash
DOCKER_CONFIG=/tmp/chatwoot-docker-config \
DOCKER_HOST=unix:///Users/ouzhouyou/.colima/default/docker.sock \
docker-compose -p chatwoot-preview \
  -f /tmp/chatwoot-preview-compose.yml \
  -f /tmp/chatwoot-preview-local.override.yml \
  ps

curl --noproxy localhost,127.0.0.1 -I http://127.0.0.1:3000/
```

## 6. 测试建议

后端 Group Messaging 测试：

```bash
bundle exec rspec spec/services/group_messaging
```

前端消息注册表测试：

```bash
pnpm test app/javascript/dashboard/channels/messageRendererRegistry.spec.js
```

关键验收项：

- 同一个群只创建一个群 Contact、ContactInbox 和 Conversation。
- 相同 `inbox_id + external_event_id` 不生成重复消息。
- 消息返回并展示 `extensions.actor` 快照。
- 群 Contact 继续支持 CRM 标签、备注和自定义属性。
- 未注册的 provider 或 message kind 回退到通用消息 renderer。
- 坐席回复通过 provider adapter 投递并保存外部 message ID。
- 原有一对一 Inbox、CRM、消息和回复流程不受影响。

## 7. 服务器部署 Runbook

以下流程假设服务器当前运行的是官方 `v4.17.1` 或同等数据库结构，并且使用 Docker Compose 管理 `rails`、`sidekiq`、`postgres` 和 `redis` 服务。

### 7.1 发布前检查

先在服务器确认当前项目、容器和镜像：

```bash
docker compose ps
docker compose images
docker volume ls
```

确认服务器上使用的是生产 Compose 配置，不要把本地开发覆盖文件和 Vite 服务带到服务器。

建议先暂停 Web 和 Sidekiq 的流量入口，或者在低峰期执行迁移和容器替换。不要执行：

```bash
docker compose down -v
```

`-v` 会删除数据库和 Redis volume。

### 7.2 本地构建生产镜像

在本 worktree 中执行完整生产构建：

```bash
cd /Users/ouzhouyou/dev/chatwoot/.worktrees/group-messaging-v4.17.1

DOCKER_CONFIG=/tmp/chatwoot-docker-config \
DOCKER_HOST=unix:///Users/ouzhouyou/.colima/default/docker.sock \
docker build --progress=plain \
  -f docker/Dockerfile \
  -t chatwoot-preview:group-messaging-v4.17.1 \
  .
```

构建后确认镜像存在：

```bash
docker image inspect chatwoot-preview:group-messaging-v4.17.1 \
  --format '{{.Id}} {{.Created}}'
```

### 7.2.1 在服务器上直接使用源码构建

如果部署要求服务器本地构建镜像，不需要执行 `docker save`。先把本 worktree 的源码同步到服务器；本次变更包含未提交文件，不能只在服务器 checkout 原始 `v4.17.1` tag：

```bash
rsync -az \
  --exclude '.git' \
  --exclude '.env' \
  --exclude 'node_modules' \
  --exclude 'tmp' \
  --exclude 'log' \
  --exclude 'storage' \
  /Users/ouzhouyou/dev/chatwoot/.worktrees/group-messaging-v4.17.1/ \
  deploy@SERVER:/opt/chatwoot-group-messaging/
```

服务器上执行生产构建：

```bash
cd /opt/chatwoot-group-messaging

docker build --progress=plain \
  -f docker/Dockerfile \
  -t chatwoot-preview:group-messaging-v4.17.1 \
  --build-arg RAILS_ENV=production \
  --build-arg BUNDLE_WITHOUT='development:test' \
  --build-arg EXECJS_RUNTIME=Disabled \
  --build-arg RAILS_SERVE_STATIC_FILES=true \
  .
```

确认镜像后，再按本 Runbook 的数据库备份、migration 和应用容器替换步骤继续执行。服务器构建时必须使用生产 Dockerfile 配置，不要使用 `group-messaging-dev` 镜像参数，也不要把 Vite 开发服务部署到生产环境。

### 7.3 导出并传到服务器

镜像较大时使用 gzip 压缩：

```bash
docker save chatwoot-preview:group-messaging-v4.17.1 \
  | gzip > /tmp/chatwoot-preview-group-messaging-v4.17.1.tar.gz

scp /tmp/chatwoot-preview-group-messaging-v4.17.1.tar.gz \
  deploy@SERVER:/tmp/
```

如果服务器可以访问私有镜像仓库，也可以改用 `docker tag`、`docker push` 和服务器上的 `docker pull`，但服务器 Compose 中的 image tag 必须保持一致。

### 7.4 服务器备份数据库

在替换镜像或执行 migration 前先备份 PostgreSQL。以下命令使用 Compose 服务名 `postgres`；如果服务器服务名不同，替换最后一个参数：

```bash
BACKUP_FILE="/var/backups/chatwoot-$(date +%Y%m%d-%H%M%S).dump"

docker compose exec -T postgres \
  pg_dump -U postgres -Fc chatwoot > "$BACKUP_FILE"

ls -lh "$BACKUP_FILE"
```

确认备份文件非空后再继续。不要覆盖之前的备份。

### 7.5 加载新镜像

在服务器执行：

```bash
gunzip -c /tmp/chatwoot-preview-group-messaging-v4.17.1.tar.gz \
  | docker load

docker image inspect chatwoot-preview:group-messaging-v4.17.1 \
  --format '{{.Id}} {{.Created}}'
```

把服务器生产 Compose 或单独的 override 文件中的 `rails`、`sidekiq` image 改为：

```yaml
services:
  rails:
    image: chatwoot-preview:group-messaging-v4.17.1
  sidekiq:
    image: chatwoot-preview:group-messaging-v4.17.1
```

不要修改 `postgres`、`redis` 的 image、volume 或数据库环境变量。

### 7.6 使用新镜像执行数据库迁移

先确认 Compose 解析到的是新镜像：

```bash
docker compose config | rg 'group-messaging-v4.17.1'
```

然后使用新 Rails 镜像执行 migration：

```bash
docker compose run --rm --no-deps rails \
  bundle exec rails db:migrate
```

检查迁移状态：

```bash
docker compose run --rm --no-deps rails \
  bundle exec rails db:migrate:status
```

本次主要涉及：

- `channel_group_messaging` 表
- contacts、conversations、messages 的 `extensions`
- messages 的 `external_event_id` 及幂等索引
- v4.17.1 `contacts.contact_type` 兼容转换

### 7.7 替换 Rails 和 Sidekiq

只重建应用容器，保留数据库和 Redis：

```bash
docker compose up -d --no-build --no-deps --force-recreate rails sidekiq
```

查看日志：

```bash
docker compose logs --tail=100 rails
docker compose logs --tail=100 sidekiq
```

如果生产环境通过 Nginx、Caddy 或负载均衡器转发，请确认它仍然指向 Rails 暴露的原端口。生产镜像不需要启动 Vite。

### 7.8 部署验收

```bash
docker compose ps
curl -fsS -I https://YOUR_CHATWOOT_DOMAIN/
```

检查 Rails 是否使用新版本代码和数据库：

```bash
docker compose exec rails bundle exec rails runner \
  'puts({environment: Rails.env, contacts: Contact.count, conversations: Conversation.count, messages: Message.count}.inspect)'
```

然后在后台验证：

- 登录和现有 Inbox 正常打开。
- 原有会话和 CRM 联系人仍然存在。
- 能创建 `GroupMessaging` Inbox。
- webhook 能创建群 Contact、Conversation 和 Message。
- 重复 webhook 不会产生重复消息。
- 坐席回复能进入 Sidekiq 并投递到 provider adapter。

### 7.9 回滚

如果只是应用启动或前端资源问题，先恢复旧镜像并重建 Rails/Sidekiq：

```bash
docker compose up -d --no-build --no-deps --force-recreate rails sidekiq
```

前提是 Compose 已恢复到旧的 `v4.17.1` image tag。

如果 migration 已经改变了数据类型或写入了新结构，不要直接盲目执行 `db:rollback`。先保留日志和当前数据库备份，再根据 migration 是否可逆决定回滚；必要时使用发布前的 PostgreSQL dump 恢复到独立数据库验证后再切换。
