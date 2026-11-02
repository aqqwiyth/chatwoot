<script setup>
import CommerceCard from 'shared/components/CommerceCard.vue';
import { useMessageContext } from '../provider';

const { contentAttributes } = useMessageContext();
</script>

<template>
  <div class="flex flex-col gap-2">
    <CommerceCard v-for="item in contentAttributes.items" :key="item.title" :item="item" />
  </div>
</template>
