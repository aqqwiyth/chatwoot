<script setup>
import { computed, reactive } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import router from '../../../../index';
import PageHeader from '../../SettingsSubPageHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const { t } = useI18n();
const form = reactive({
  channelName: '',
  openKfid: '',
  secret: '',
  callbackToken: '',
  encodingAesKey: '',
  corpId: '',
});
const v$ = useVuelidate(
  {
    channelName: { required },
    openKfid: { required },
    secret: { required },
    callbackToken: { required },
    encodingAesKey: { required },
    corpId: { required },
  },
  form
);
const uiFlags = computed(() => store.getters['inboxes/getUIFlags']);

const createChannel = async () => {
  v$.value.$touch();
  if (v$.value.$invalid) return;

  try {
    const inbox = await store.dispatch('inboxes/createChannel', {
      name: form.channelName.trim(),
      channel: {
        type: 'wecom_customer_service',
        open_kfid: form.openKfid.trim(),
        secret: form.secret.trim(),
        callback_token: form.callbackToken.trim(),
        encoding_aes_key: form.encodingAesKey.trim(),
        corp_id: form.corpId.trim(),
      },
    });
    router.replace({
      name: 'settings_inbox_finish',
      params: { page: 'new', inbox_id: inbox.id },
    });
  } catch (error) {
    useAlert(
      error.response?.data?.message ||
        t('INBOX_MGMT.ADD.WECOM_CUSTOMER_SERVICE.API.ERROR_MESSAGE')
    );
  }
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
        <input
          v-model="form.channelName"
          type="text"
          @blur="v$.channelName.$touch"
        />
      </label>
      <label :class="{ error: v$.openKfid.$error }">
        {{ $t('INBOX_MGMT.ADD.WECOM_CUSTOMER_SERVICE.OPEN_KFID.LABEL') }}
        <input v-model="form.openKfid" type="text" @blur="v$.openKfid.$touch" />
      </label>
      <label :class="{ error: v$.secret.$error }">
        {{ $t('INBOX_MGMT.ADD.WECOM_CUSTOMER_SERVICE.SECRET.LABEL') }}
        <input v-model="form.secret" type="password" @blur="v$.secret.$touch" />
      </label>
      <label :class="{ error: v$.callbackToken.$error }">
        {{ $t('INBOX_MGMT.ADD.WECOM_CUSTOMER_SERVICE.CALLBACK_TOKEN.LABEL') }}
        <input
          v-model="form.callbackToken"
          type="password"
          @blur="v$.callbackToken.$touch"
        />
      </label>
      <label :class="{ error: v$.encodingAesKey.$error }">
        {{ $t('INBOX_MGMT.ADD.WECOM_CUSTOMER_SERVICE.ENCODING_AES_KEY.LABEL') }}
        <input
          v-model="form.encodingAesKey"
          type="password"
          @blur="v$.encodingAesKey.$touch"
        />
      </label>
      <label :class="{ error: v$.corpId.$error }">
        {{ $t('INBOX_MGMT.ADD.WECOM_CUSTOMER_SERVICE.CORP_ID.LABEL') }}
        <input v-model="form.corpId" type="text" @blur="v$.corpId.$touch" />
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
