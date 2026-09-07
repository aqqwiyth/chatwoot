<template>
  <div v-if="!provider" class="wizard-body small-12 medium-9 columns height-auto">
    <page-header header-title="Group messaging" header-content="Choose a group messaging provider." />
    <div class="channel-list">
      <channel-selector
        v-for="item in providers"
        :key="item.key"
        :class="{ disabled: !item.enabled }"
        :title="item.title"
        :icon="item.icon"
        @click="selectProvider(item)"
      />
    </div>
  </div>
  <div v-else class="wizard-body small-9 columns">
    <page-header :header-title="selectedProvider.title" header-content="Configure your provider." />
    <form class="row" @submit.prevent="createChannel">
      <div class="medium-8 columns">
        <label>Channel name<input v-model.trim="channelName" required /></label>
        <label>Identifier<input v-model.trim="identifier" required /></label>
        <template v-if="provider === 'wecom'">
          <label>企业微信公司名字<input v-model.trim="companyName" required /></label>
          <label>企业微信公司 ID<input v-model.trim="companyId" required /></label>
          <label>允许的群主 ID（JSON 数组）<textarea v-model="allowedGroupOwners" rows="2" /></label>
          <label>允许的群 ID（JSON 数组）<textarea v-model="allowedGroupIds" rows="2" /></label>
          <label>忽略的群 ID（JSON 数组）<textarea v-model="ignoredGroupIds" rows="2" /></label>
          <label>团队分流规则（JSON 数组）<textarea v-model="routingRules" rows="3" placeholder='[{"team_id":1,"group_owners":["owner-id"],"group_ids":["group-id"]}]' /></label>
          <label>发送账号 ID（JSON 数组）<textarea v-model="sendAccountId" rows="2" /></label>
          <label>发送 RPA 服务地址<input v-model.trim="sendBaseUrl" /></label>
          <label>Webhook Secret<input v-model.trim="webhookSecret" /></label>
        </template>
      </div>
      <div class="form-actions">
        <NextButton
          :is-loading="uiFlags.isCreating"
          type="submit"
          solid
          blue
          label="创建渠道"
        />
      </div>
    </form>
  </div>
</template>

<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import router from '../../../../index';
import PageHeader from '../../SettingsSubPageHeader.vue';
import ChannelSelector from 'dashboard/components/ChannelSelector.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: { PageHeader, ChannelSelector, NextButton },
  data() {
    return {
      channelName: '',
      provider: '',
      identifier: '',
      companyName: '',
      companyId: '',
      allowedGroupOwners: '[]',
      allowedGroupIds: '[]',
      ignoredGroupIds: '[]',
      routingRules: '[]',
      sendAccountId: '[]',
      sendBaseUrl: '',
      webhookSecret: '',
    };
  },
  computed: {
    ...mapGetters({ uiFlags: 'inboxes/getUIFlags' }),
    providers() {
      return [
        { key: 'wecom', title: '企业微信（会话存档）', enabled: true, icon: 'i-lucide-message-circle' },
        { key: 'wecom_rpa', title: '企业微信（RPA）', enabled: false, icon: 'i-lucide-bot' },
        { key: 'feishu', title: '飞书群', enabled: false, icon: 'i-lucide-messages-square' },
        { key: 'dingtalk', title: '钉钉群', enabled: false, icon: 'i-lucide-message-square' },
      ];
    },
    selectedProvider() {
      return this.providers.find(item => item.key === this.provider) || {};
    },
  },
  methods: {
    selectProvider(item) {
      if (item.enabled) this.provider = item.key;
    },
    async createChannel() {
      const parseArray = value => {
        try {
          const parsed = JSON.parse(value || '[]');
          if (!Array.isArray(parsed)) throw new Error();
          return parsed;
        } catch (error) {
          useAlert('群 ID 配置必须是 JSON 数组');
          return null;
        }
      };
      const allowedGroupOwners = parseArray(this.allowedGroupOwners);
      const allowedGroupIds = parseArray(this.allowedGroupIds);
      const ignoredGroupIds = parseArray(this.ignoredGroupIds);
      const sendAccountId = parseArray(this.sendAccountId);
      const routingRules = parseArray(this.routingRules);
      if (!allowedGroupOwners || !allowedGroupIds || !ignoredGroupIds || !sendAccountId || !routingRules) return;
      const channel = {
        type: 'group_messaging',
        provider: this.provider,
        identifier: this.identifier,
        provider_config: {
          company_name: this.companyName,
          company_id: this.companyId,
          allowed_group_owners: allowedGroupOwners,
          allowed_group_ids: allowedGroupIds,
          ignored_group_ids: ignoredGroupIds,
          routing_rules: routingRules,
          send_account_id: sendAccountId,
          send_base_url: this.sendBaseUrl,
          send_url: this.sendBaseUrl,
          webhook_secret: this.webhookSecret,
        },
      };
      try {
        const inbox = await this.$store.dispatch('inboxes/createChannel', {
          name: this.channelName,
          channel,
        });
        router.replace({ name: 'settings_inboxes_add_agents', params: { page: 'new', inbox_id: inbox.id } });
      } catch (error) {
        useAlert(error.response?.data?.message || '创建渠道失败，请检查配置');
      }
    },
  },
};
</script>

<style scoped>
.height-auto { height: auto; }
.channel-list {
  margin-top: var(--space-medium);
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: var(--space-normal);
}
.channel-list :deep(button) { width: 100%; }
.form-actions { margin-top: var(--space-large); }
</style>
