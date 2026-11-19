<script setup>
import { onMounted, ref, watch } from 'vue';

const props = defineProps({
  type: { type: String, required: true },
  openid: { type: [String, Number], required: true },
});
const container = ref(null);

const bind = () => {
  const element = document.createElement('ww-open-data');
  element.setAttribute('type', props.type);
  element.setAttribute('openid', String(props.openid));
  container.value.replaceChildren(element);
  window.WWOpenData.bind(element);
};

onMounted(bind);
watch(() => [props.type, props.openid], bind);
</script>

<template><span ref="container" /></template>
