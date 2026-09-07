<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useWhatsappEmbeddedSignup } from 'dashboard/composables/useWhatsappEmbeddedSignup';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import whatsappChannel from 'dashboard/api/channel/whatsappChannel';
import inboxMixin from 'shared/mixins/inboxMixin';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import SettingsAccordion from 'dashboard/components-next/Settings/SettingsAccordion.vue';
import ImapSettings from '../ImapSettings.vue';
import SmtpSettings from '../SmtpSettings.vue';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import NextButton from 'dashboard/components-next/button/Button.vue';
import TextArea from 'next/textarea/TextArea.vue';
import { sanitizeAllowedDomains } from 'dashboard/helper/URLHelper';
import WhatsappBusinessManagementToken from './WhatsappBusinessManagementToken.vue';

export default {
  components: {
    SettingsFieldSection,
    SettingsToggleSection,
    SettingsAccordion,
    ImapSettings,
    SmtpSettings,
    NextButton,
    TextArea,
    WhatsappBusinessManagementToken,
  },
  mixins: [inboxMixin],
  props: {
    inbox: {
      type: Object,
      default: () => ({}),
    },
  },
  setup() {
    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    return { v$: useVuelidate(), runEmbeddedSignup };
  },
  data() {
    return {
      hmacMandatory: false,
      allowMobileWebview: false,
      whatsAppInboxAPIKey: '',
      isSyncingTemplates: false,
      allowedDomains: '',
      isUpdatingAllowedDomains: false,
      isSettingDefaults: false,
      isReconfiguring: false,
      isUpdatingGroupMessaging: false,
      wecomCompanyName: '',
      wecomCompanyId: '',
      wecomAllowedGroupOwners: '[]',
      wecomAllowedGroupIds: '[]',
      wecomIgnoredGroupIds: '[]',
      wecomRoutingRules: '[]',
      wecomSendAccountId: '[]',
      wecomSendBaseUrl: '',
      wecomWebhookSecret: '',
    };
  },
  validations: {
    whatsAppInboxAPIKey: { required },
  },
  computed: {
    ...mapGetters({
      accountId: 'getCurrentAccountId',
      isFeatureEnabledonAccount: 'accounts/isFeatureEnabledonAccount',
      isOnChatwootCloud: 'globalConfig/isOnChatwootCloud',
    }),
    isEmbeddedSignupWhatsApp() {
      return this.inbox.provider_config?.source === 'embedded_signup';
    },
    showWhatsAppReconfigure() {
      return (
        this.isEmbeddedSignupWhatsApp &&
        this.isFeatureEnabledonAccount(
          this.accountId,
          this.isOnChatwootCloud
            ? FEATURE_FLAGS.WHATSAPP_EMBEDDED_SIGNUP_FLOW
            : FEATURE_FLAGS.WHATSAPP_RECONFIGURE
        )
      );
    },
    isForwardingEnabled() {
      return !!this.inbox.forwarding_enabled;
    },
    isAGroupMessagingChannel() {
      return this.inbox.channel_type === 'Channel::GroupMessaging';
    },
    isWecomGroupMessaging() {
      return this.isAGroupMessagingChannel && this.inbox.provider === 'wecom';
    },
  },
  watch: {
    inbox() {
      this.setDefaults();
    },
    allowMobileWebview() {
      if (!this.isSettingDefaults) this.handleMobileWebviewFlag();
    },
    hmacMandatory() {
      if (!this.isSettingDefaults && this.isAWebWidgetInbox)
        this.handleHmacFlag();
    },
  },
  mounted() {
    this.setDefaults();
  },
  methods: {
    setDefaults() {
      this.isSettingDefaults = true;
      this.hmacMandatory = this.inbox.hmac_mandatory || false;
      this.allowMobileWebview = (
        this.inbox.selected_feature_flags || []
      ).includes('allow_mobile_webview');
      this.allowedDomains = this.inbox.allowed_domains || '';
      if (this.isAGroupMessagingChannel) {
        const config = this.inbox.provider_config || {};
        if (this.isWecomGroupMessaging) {
          this.wecomCompanyName = config.company_name || '';
          this.wecomCompanyId = config.company_id || '';
          this.wecomAllowedGroupOwners = JSON.stringify(
            config.allowed_group_owners || [],
            null,
            2
          );
          this.wecomAllowedGroupIds = JSON.stringify(
            config.allowed_group_ids || [],
            null,
            2
          );
          this.wecomIgnoredGroupIds = JSON.stringify(
            config.ignored_group_ids || [],
            null,
            2
          );
          this.wecomRoutingRules = JSON.stringify(
            config.routing_rules || [],
            null,
            2
          );
          this.wecomSendAccountId = JSON.stringify(
            config.send_account_id || [],
            null,
            2
          );
          this.wecomSendBaseUrl = config.send_base_url || config.send_url || '';
          this.wecomWebhookSecret = config.webhook_secret || '';
        }
      }
      this.$nextTick(() => {
        this.isSettingDefaults = false;
      });
    },
    handleHmacFlag() {
      this.updateInbox();
    },
    async updateWecomConfig() {
      if (!this.isWecomGroupMessaging) return;
      const parseArray = value => {
        try {
          const parsed = JSON.parse(value || '[]');
          if (!Array.isArray(parsed)) throw new Error();
          return parsed;
        } catch (error) {
          useAlert('群组 ID、路由规则和发送账号必须是有效 JSON 数组');
          return null;
        }
      };
      const allowedGroupOwners = parseArray(this.wecomAllowedGroupOwners);
      const allowedGroupIds = parseArray(this.wecomAllowedGroupIds);
      const ignoredGroupIds = parseArray(this.wecomIgnoredGroupIds);
      const routingRules = parseArray(this.wecomRoutingRules);
      const sendAccountId = parseArray(this.wecomSendAccountId);
      if (
        [
          allowedGroupOwners,
          allowedGroupIds,
          ignoredGroupIds,
          routingRules,
          sendAccountId,
        ].some(value => value === null)
      ) {
        return;
      }
      const providerConfig = {
        ...(this.inbox.provider_config || {}),
        company_name: this.wecomCompanyName.trim(),
        company_id: this.wecomCompanyId.trim(),
        allowed_group_owners: allowedGroupOwners,
        allowed_group_ids: allowedGroupIds,
        ignored_group_ids: ignoredGroupIds,
        routing_rules: routingRules,
        send_account_id: sendAccountId,
        send_base_url: this.wecomSendBaseUrl.trim(),
        send_url: this.wecomSendBaseUrl.trim(),
        webhook_secret: this.wecomWebhookSecret.trim(),
      };
      if (!providerConfig.company_name || !providerConfig.company_id) {
        useAlert('企业微信公司名称和公司 ID 不能为空');
        return;
      }
      this.isUpdatingGroupMessaging = true;
      try {
        await this.$store.dispatch('inboxes/updateInbox', {
          id: this.inbox.id,
          formData: false,
          channel: { provider_config: providerConfig },
        });
        useAlert('企业微信配置已更新');
      } catch (error) {
        useAlert(error.response?.data?.message || '企业微信配置更新失败');
      } finally {
        this.isUpdatingGroupMessaging = false;
      }
    },
    async updateInbox() {
      try {
        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {
            hmac_mandatory: this.hmacMandatory,
          },
        };
        await this.$store.dispatch('inboxes/updateInbox', payload);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      }
    },
    async handleMobileWebviewFlag() {
      try {
        const currentFlags = this.inbox.selected_feature_flags || [];
        const selectedFlags = this.allowMobileWebview
          ? [...currentFlags, 'allow_mobile_webview']
          : currentFlags.filter(f => f !== 'allow_mobile_webview');

        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {
            selected_feature_flags: selectedFlags,
          },
        };
        await this.$store.dispatch('inboxes/updateInbox', payload);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      }
    },
    async updateAllowedDomains() {
      this.isUpdatingAllowedDomains = true;
      const sanitizedAllowedDomains = sanitizeAllowedDomains(
        this.allowedDomains
      );
      try {
        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {
            allowed_domains: sanitizedAllowedDomains,
          },
        };
        await this.$store.dispatch('inboxes/updateInbox', payload);
        this.allowedDomains = sanitizedAllowedDomains;
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      } finally {
        this.isUpdatingAllowedDomains = false;
      }
    },
    async updateWhatsAppInboxAPIKey() {
      try {
        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {},
        };

        payload.channel.provider_config = {
          ...this.inbox.provider_config,
          api_key: this.whatsAppInboxAPIKey,
        };

        await this.$store.dispatch('inboxes/updateInbox', payload);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      }
    },
    async reconfigureWhatsApp() {
      this.isReconfiguring = true;
      try {
        const credentials = await this.runEmbeddedSignup();
        // User dismissed the Meta popup without completing signup.
        if (!credentials) return;

        await whatsappChannel.reauthorizeWhatsApp({
          inboxId: this.inbox.id,
          ...credentials,
        });
        useAlert(
          this.$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_RECONFIGURE_SUCCESS')
        );
      } catch (error) {
        useAlert(
          this.$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_RECONFIGURE_ERROR')
        );
      } finally {
        this.isReconfiguring = false;
      }
    },
    async syncTemplates() {
      this.isSyncingTemplates = true;
      try {
        await this.$store.dispatch('inboxes/syncTemplates', this.inbox.id);
        useAlert(
          this.$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_SUCCESS')
        );
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      } finally {
        this.isSyncingTemplates = false;
      }
    },
  },
};
</script>

<template>
  <div v-if="isATwilioChannel">
    <SettingsFieldSection
      :label="$t('INBOX_MGMT.ADD.TWILIO.API_CALLBACK.TITLE')"
      :help-text="$t('INBOX_MGMT.ADD.TWILIO.API_CALLBACK.SUBTITLE')"
    >
      <woot-code :script="inbox.callback_webhook_url" lang="html" />
    </SettingsFieldSection>
    <SettingsFieldSection
      v-if="isATwilioWhatsAppChannel"
      :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_TITLE')"
      :help-text="
        $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_SUBHEADER')
      "
    >
      <NextButton :disabled="isSyncingTemplates" @click="syncTemplates">
        {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_BUTTON') }}
      </NextButton>
    </SettingsFieldSection>
  </div>

  <div v-else-if="isALineChannel">
    <SettingsFieldSection
      :label="$t('INBOX_MGMT.ADD.LINE_CHANNEL.API_CALLBACK.TITLE')"
      :help-text="$t('INBOX_MGMT.ADD.LINE_CHANNEL.API_CALLBACK.SUBTITLE')"
    >
      <woot-code :script="inbox.callback_webhook_url" lang="html" />
    </SettingsFieldSection>
  </div>
  <div v-else-if="isAWebWidgetInbox">
    <div class="space-y-4">
      <SettingsToggleSection
        :header="$t('INBOX_MGMT.SETTINGS_POPUP.ALLOWED_DOMAINS.TITLE')"
        :description="
          $t('INBOX_MGMT.SETTINGS_POPUP.ALLOWED_DOMAINS.DESCRIPTION')
        "
        hide-toggle
      >
        <template #editor>
          <TextArea
            v-model="allowedDomains"
            :placeholder="
              $t('INBOX_MGMT.SETTINGS_POPUP.ALLOWED_DOMAINS.PLACEHOLDER')
            "
            auto-height
            resize
            class="w-full [&>div]:!bg-transparent [&>div]:!border-none [&>div]:!border-0 [&>div]:px-0 [&>div]:pb-0 [&>div]:pt-0"
          />
          <div class="mt-3 flex justify-end">
            <NextButton
              :label="$t('INBOX_MGMT.SETTINGS_POPUP.UPDATE')"
              :is-loading="isUpdatingAllowedDomains"
              @click="updateAllowedDomains"
            />
          </div>
        </template>
      </SettingsToggleSection>
      <SettingsToggleSection
        v-model="allowMobileWebview"
        :header="$t('INBOX_MGMT.SETTINGS_POPUP.ALLOW_MOBILE_WEBVIEW.LABEL')"
        :description="
          $t('INBOX_MGMT.SETTINGS_POPUP.ALLOW_MOBILE_WEBVIEW.SUBTITLE')
        "
      />
    </div>

    <SettingsAccordion
      :title="$t('INBOX_MGMT.SETTINGS_POPUP.IDENTITY_VALIDATION.TITLE')"
      class="mt-6"
    >
      <SettingsToggleSection
        :header="$t('INBOX_MGMT.SETTINGS_POPUP.IDENTITY_VALIDATION.TITLE')"
        :description="
          $t('INBOX_MGMT.SETTINGS_POPUP.IDENTITY_VALIDATION.DESCRIPTION')
        "
        hide-toggle
      >
        <template #editor>
          <p class="mb-1 text-sm font-medium text-n-slate-12">
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.IDENTITY_VALIDATION.SECRET_KEY') }}
          </p>
          <woot-code :script="inbox.hmac_token" />
          <p class="mt-1.5 text-label-small text-n-slate-11">
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.HMAC_DESCRIPTION') }}
            <a
              target="_blank"
              rel="noopener noreferrer"
              href="https://www.chatwoot.com/docs/product/channels/live-chat/sdk/identity-validation/"
              class="text-n-blue-11 hover:underline text-label-small"
            >
              {{
                $t('INBOX_MGMT.SETTINGS_POPUP.IDENTITY_VALIDATION.VIEW_DOCS')
              }}
            </a>
          </p>
        </template>
      </SettingsToggleSection>

      <SettingsToggleSection
        v-model="hmacMandatory"
        :header="
          $t('INBOX_MGMT.SETTINGS_POPUP.IDENTITY_VALIDATION.REQUIRE_LABEL')
        "
        :description="
          $t(
            'INBOX_MGMT.SETTINGS_POPUP.IDENTITY_VALIDATION.REQUIRE_DESCRIPTION'
          )
        "
      />
    </SettingsAccordion>
  </div>
  <div v-else-if="isAPIInbox">
    <SettingsFieldSection
      :label="$t('INBOX_MGMT.SETTINGS_POPUP.INBOX_IDENTIFIER')"
      :help-text="$t('INBOX_MGMT.SETTINGS_POPUP.INBOX_IDENTIFIER_SUB_TEXT')"
    >
      <woot-code :script="inbox.inbox_identifier" />
    </SettingsFieldSection>

    <SettingsFieldSection
      :label="$t('INBOX_MGMT.SETTINGS_POPUP.HMAC_VERIFICATION')"
      :help-text="$t('INBOX_MGMT.SETTINGS_POPUP.HMAC_DESCRIPTION')"
    >
      <woot-code :script="inbox.hmac_token" />
    </SettingsFieldSection>
    <SettingsFieldSection
      :label="$t('INBOX_MGMT.SETTINGS_POPUP.HMAC_MANDATORY_VERIFICATION')"
      :help-text="$t('INBOX_MGMT.SETTINGS_POPUP.HMAC_MANDATORY_DESCRIPTION')"
    >
      <div class="flex gap-2 items-center">
        <input
          id="hmacMandatory"
          v-model="hmacMandatory"
          type="checkbox"
          @change="handleHmacFlag"
        />
        <label for="hmacMandatory" class="text-body-main text-n-slate-12">
          {{ $t('INBOX_MGMT.EDIT.ENABLE_HMAC.LABEL') }}
        </label>
      </div>
    </SettingsFieldSection>
  </div>
  <div v-else-if="isAnEmailChannel">
    <div>
      <SettingsFieldSection
        :label="$t('INBOX_MGMT.SETTINGS_POPUP.FORWARD_EMAIL_TITLE')"
        :help-text="
          isForwardingEnabled
            ? $t('INBOX_MGMT.SETTINGS_POPUP.FORWARD_EMAIL_SUB_TEXT')
            : ''
        "
      >
        <woot-code
          v-if="isForwardingEnabled"
          :script="inbox.forward_to_email"
        />
        <div
          v-else
          class="py-2 px-3 bg-n-amber-3 outline-n-amber-4 text-n-amber-11 outline outline-1 -outline-offset-1 rounded-xl"
        >
          <p class="text-body-para mb-0">
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.FORWARD_EMAIL_NOT_CONFIGURED') }}
          </p>
        </div>
      </SettingsFieldSection>
    </div>
    <ImapSettings :inbox="inbox" />
    <SmtpSettings v-if="inbox.imap_enabled" :inbox="inbox" />
  </div>
  <div v-else-if="isAGroupMessagingChannel">
    <SettingsFieldSection
      v-if="isWecomGroupMessaging"
      label="企业微信配置"
      help-text="编辑企业微信公司及群聊相关 ID"
    >
      <div class="group-messaging-fields">
        <p class="help-text">
          允许的群主 ID 与允许的群 ID 为“或”关系，任一命中即可进入；忽略的群 ID 优先级最高，命中后不会进入。
        </p>
        <woot-input v-model.trim="wecomCompanyName" label="企业微信公司名称" />
        <woot-input v-model.trim="wecomCompanyId" label="企业微信公司 ID" />
        <label
          >允许的群主 ID（JSON 数组）<textarea
            v-model="wecomAllowedGroupOwners"
            rows="2"
        /></label>
        <label
          >允许的群 ID（JSON 数组）<textarea v-model="wecomAllowedGroupIds" rows="2"
        /></label>
        <label
          >忽略的群 ID（JSON 数组）<textarea v-model="wecomIgnoredGroupIds" rows="2"
        /></label>
        <label
          >团队分流规则（暂留空）<textarea v-model="wecomRoutingRules" rows="3"
        /></label>
        <label
          >发送账号 ID（JSON 数组）<textarea v-model="wecomSendAccountId" rows="2"
        /></label>
        <woot-input v-model.trim="wecomSendBaseUrl" label="发送 RPA 服务地址" />
        <woot-input v-model.trim="wecomWebhookSecret" label="Webhook Secret" />
      </div>
      <NextButton :is-loading="isUpdatingGroupMessaging" solid blue @click="updateWecomConfig">
        保存企业微信配置
      </NextButton>
    </SettingsFieldSection>
    <SettingsFieldSection v-else label="Provider 配置" help-text="该群聊 provider 暂无专用配置编辑页">
      <woot-code :script="JSON.stringify(inbox.provider_config || {}, null, 2)" />
    </SettingsFieldSection>
  </div>
  <div v-else-if="isAWhatsAppChannel && !isATwilioChannel">
    <div v-if="inbox.provider_config">
      <!-- Embedded Signup Section -->
      <template v-if="isEmbeddedSignupWhatsApp">
        <SettingsFieldSection
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_WEBHOOK_TITLE')"
          :help-text="
            $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_WEBHOOK_SUBHEADER')
          "
        >
          <woot-code :script="inbox.provider_config.webhook_verify_token" />
        </SettingsFieldSection>
        <SettingsFieldSection
          v-if="showWhatsAppReconfigure"
          :label="
            $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_EMBEDDED_SIGNUP_TITLE')
          "
          :help-text="
            $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_EMBEDDED_SIGNUP_DESCRIPTION')
          "
        >
          <NextButton
            :is-loading="isReconfiguring"
            :disabled="isReconfiguring"
            @click="reconfigureWhatsApp"
          >
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_RECONFIGURE_BUTTON') }}
          </NextButton>
        </SettingsFieldSection>
      </template>

      <!-- Manual Setup Section -->
      <template v-else-if="!isEmbeddedSignupWhatsApp">
        <SettingsFieldSection
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_WEBHOOK_TITLE')"
          :help-text="
            $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_WEBHOOK_SUBHEADER')
          "
        >
          <woot-code :script="inbox.provider_config.webhook_verify_token" />
        </SettingsFieldSection>
        <SettingsFieldSection
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_TITLE')"
          :help-text="
            $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_SUBHEADER')
          "
        >
          <woot-code :script="inbox.provider_config.api_key" />
        </SettingsFieldSection>
        <SettingsFieldSection
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_TITLE')"
          :help-text="
            $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_SUBHEADER')
          "
        >
          <div
            class="flex flex-1 justify-between items-center whatsapp-settings--content"
          >
            <woot-input
              v-model="whatsAppInboxAPIKey"
              type="text"
              class="flex-1 mr-2 [&>input]:!mb-0"
              :placeholder="
                $t(
                  'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_PLACEHOLDER'
                )
              "
            />
            <NextButton
              :disabled="v$.whatsAppInboxAPIKey.$invalid"
              @click="updateWhatsAppInboxAPIKey"
            >
              {{
                $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_BUTTON')
              }}
            </NextButton>
          </div>
        </SettingsFieldSection>
      </template>
      <WhatsappBusinessManagementToken
        v-if="
          isOnChatwootCloud &&
          inbox.provider === 'whatsapp_cloud' &&
          isEmbeddedSignupWhatsApp
        "
        :inbox="inbox"
      />
      <SettingsFieldSection
        :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_TITLE')"
        :help-text="
          $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_SUBHEADER')
        "
      >
        <NextButton :disabled="isSyncingTemplates" @click="syncTemplates">
          {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_BUTTON') }}
        </NextButton>
      </SettingsFieldSection>
    </div>
  </div>
</template>

<style lang="scss" scoped>
.whatsapp-settings--content {
  :deep(input) {
    margin-bottom: 0;
  }
}
.group-messaging-fields {
  display: grid;
  gap: var(--space-normal);
  margin-bottom: var(--space-normal);

  textarea {
    width: 100%;
    padding: var(--space-small);
    border: 1px solid var(--color-border);
    border-radius: var(--border-radius-normal);
    font-family: var(--font-family-mono);
  }
}
</style>
