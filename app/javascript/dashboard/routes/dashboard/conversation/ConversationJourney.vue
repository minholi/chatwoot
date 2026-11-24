<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useNow } from '@vueuse/core';
import { useExactTimestamp } from 'shared/composables/useExactTimestamp';
import { formatDuration } from 'shared/helpers/timeHelper';
import ContactDetailsItem from './ContactDetailsItem.vue';

const props = defineProps({
  conversation: {
    type: Object,
    default: () => ({}),
  },
});

const { t } = useI18n();

const NOW_REFRESH_INTERVAL_MS = 30000;
const now = useNow({ interval: NOW_REFRESH_INTERVAL_MS });
const nowInSeconds = computed(() => Math.floor(now.value.getTime() / 1000));

const exactTimestamp = useExactTimestamp();

const isOpen = computed(() => props.conversation.status === 'open');

const timestamps = computed(() => {
  const {
    started_at: startedAt,
    opened_at: openedAt,
    human_first_reply_at: humanFirstReplyAt,
    closed_at: closedAt,
  } = props.conversation;

  return [
    {
      key: 'started',
      title: t('CONVERSATION_SIDEBAR.JOURNEY.STARTED_AT'),
      value: startedAt,
    },
    {
      key: 'opened',
      title: t('CONVERSATION_SIDEBAR.JOURNEY.OPENED_AT'),
      value: openedAt,
    },
    {
      key: 'human-first-reply',
      title: t('CONVERSATION_SIDEBAR.JOURNEY.HUMAN_FIRST_REPLY_AT'),
      value: humanFirstReplyAt,
    },
    {
      key: 'closed',
      title: t('CONVERSATION_SIDEBAR.JOURNEY.CLOSED_AT'),
      value: closedAt,
    },
  ]
    .filter(item => item.value)
    .map(item => ({ ...item, value: exactTimestamp(item.value) }));
});

// A stage still in progress is measured up to now while the conversation is open.
const durationItem = (key, title, start, end) => {
  if (!start) return null;

  const inProgress = !end && isOpen.value;
  if (!end && !inProgress) return null;

  return {
    key,
    title,
    inProgress,
    value: formatDuration((end || nowInSeconds.value) - start),
  };
};

const durations = computed(() => {
  const {
    created_at: createdAt,
    started_at: startedAt,
    opened_at: openedAt,
    human_first_reply_at: humanFirstReplyAt,
    closed_at: closedAt,
  } = props.conversation;
  if (!startedAt) return [];

  return [
    durationItem(
      'bot',
      t('CONVERSATION_SIDEBAR.JOURNEY.BOT_TIME'),
      createdAt,
      startedAt
    ),
    durationItem(
      'queue',
      t('CONVERSATION_SIDEBAR.JOURNEY.QUEUE_TIME'),
      startedAt,
      openedAt
    ),
    durationItem(
      'first-reply',
      t('CONVERSATION_SIDEBAR.JOURNEY.FIRST_REPLY_TIME'),
      openedAt,
      humanFirstReplyAt
    ),
    durationItem(
      'handling',
      t('CONVERSATION_SIDEBAR.JOURNEY.HANDLING_TIME'),
      openedAt,
      closedAt
    ),
  ].filter(Boolean);
});
</script>

<template>
  <div class="flex flex-col gap-3" :class="{ 'mb-3': timestamps.length }">
    <ContactDetailsItem
      v-for="item in timestamps"
      :key="item.key"
      :title="item.title"
      :value="item.value"
    />
    <ContactDetailsItem
      v-for="item in durations"
      :key="item.key"
      :title="item.title"
      :value="item.value"
    >
      {{ item.value }}
      <span v-if="item.inProgress" class="text-n-slate-11">
        {{ $t('CONVERSATION_SIDEBAR.JOURNEY.IN_PROGRESS') }}
      </span>
    </ContactDetailsItem>
  </div>
</template>
