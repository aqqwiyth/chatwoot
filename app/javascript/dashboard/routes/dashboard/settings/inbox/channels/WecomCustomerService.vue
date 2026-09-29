<script>
import { mapGetters } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { required, helpers } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import router from '../../../../index';
import PageHeader from '../../SettingsSubPageHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const httpsUrl = helpers.withMessage(
  'Please enter a valid HTTP or HTTPS URL',
  value => /^https?:\/\//.test(value || '')
);

export default {
  components: { PageHeader, NextButton },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      channelName: '',
      openKfid: '',
      secret: '',
      webhookUrl: '',
      callbackToken: '',
      encodingAesKey: '',
      corpId: '',
    };
  },
  computed: {
    ...mapGetters({ uiFlags: 'inboxes/getUIFlags' }),
  },
  validations: {
    channelName: { required },
    openKfid: { required },
    secret: { required },
    webhookUrl: { required, httpsUrl },
    callbackToken: { required },
    encodingAesKey: { required },
    corpId: { required },
  },
  methods: {
    async createChannel() {
      this.v$.$touch();
      if (this.v$.$invalid) return;

      try {
        const inbox = await this.$store.dispatch('inboxes/createChannel', {
          name: this.channelName.trim(),
          channel: {
            type: 'wecom_customer_service',
            open_kfid: this.openKfid.trim(),
            secret: this.secret.trim(),
            webhook_url: this.webhookUrl.trim(),
            callback_token: this.callbackToken.trim(),
            encoding_aes_key: this.encodingAesKey.trim(),
            corp_id: this.corpId.trim(),
          },
        });

        router.replace({
          name: 'settings_inbox_finish',
          params: { page: 'new', inbox_id: inbox.id },
        });
      } catch (error) {
        useAlert(
          error.response?.data?.message ||
            this.$t('INBOX_MGMT.ADD.WECOM_CUSTOMER_SERVICE.API.ERROR_MESSAGE')
        );
      }
    },
  },
};
</script>

<template>
  <div class="h-full w-full p-6 col-span-6">
    <PageHeader
      :header-title="$t('INBOX_MGMT.ADD.WECOM_CUSTOMER_SERVICE.TITLE')"
      :header-content="$t('INBOX_MGMT.ADD.WECOM_CUSTOMER_SERVICE.DESC')"
    />
    <form class="flex flex-wrap flex-col mx-0" @submit.prevent="createChannel">
      <label :class="{ error: v$.channelName.$error }">
        {{ $t('INBOX_MGMT.ADD.WECOM_CUSTOMER_SERVICE.CHANNEL_NAME.LABEL') }}
        <input v-model="channelName" type="text" @blur="v$.channelName.$touch" />
      </label>
      <label :class="{ error: v$.openKfid.$error }">
        {{ $t('INBOX_MGMT.ADD.WECOM_CUSTOMER_SERVICE.OPEN_KFID.LABEL') }}
        <input v-model="openKfid" type="text" @blur="v$.openKfid.$touch" />
      </label>
      <label :class="{ error: v$.secret.$error }">
        {{ $t('INBOX_MGMT.ADD.WECOM_CUSTOMER_SERVICE.SECRET.LABEL') }}
        <input v-model="secret" type="password" @blur="v$.secret.$touch" />
      </label>
      <label :class="{ error: v$.webhookUrl.$error }">
        {{ $t('INBOX_MGMT.ADD.WECOM_CUSTOMER_SERVICE.WEBHOOK_URL.LABEL') }}
        <input v-model="webhookUrl" type="url" @blur="v$.webhookUrl.$touch" />
      </label>
      <label :class="{ error: v$.callbackToken.$error }">
        {{ $t('INBOX_MGMT.ADD.WECOM_CUSTOMER_SERVICE.CALLBACK_TOKEN.LABEL') }}
        <input v-model="callbackToken" type="password" @blur="v$.callbackToken.$touch" />
      </label>
      <label :class="{ error: v$.encodingAesKey.$error }">
        {{ $t('INBOX_MGMT.ADD.WECOM_CUSTOMER_SERVICE.ENCODING_AES_KEY.LABEL') }}
        <input v-model="encodingAesKey" type="password" @blur="v$.encodingAesKey.$touch" />
      </label>
      <label :class="{ error: v$.corpId.$error }">
        {{ $t('INBOX_MGMT.ADD.WECOM_CUSTOMER_SERVICE.CORP_ID.LABEL') }}
        <input v-model="corpId" type="text" @blur="v$.corpId.$touch" />
      </label>
      <div class="w-full mt-4">
        <NextButton
          :is-loading="uiFlags.isCreating"
          type="submit"
          solid
          blue
          :label="$t('INBOX_MGMT.ADD.WECOM_CUSTOMER_SERVICE.SUBMIT_BUTTON')"
        />
      </div>
    </form>
  </div>
</template>
