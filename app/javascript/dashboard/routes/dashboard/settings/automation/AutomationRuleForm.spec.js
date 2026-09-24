import { nextTick, reactive } from 'vue';
import { shallowMount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import AutomationRuleForm from './AutomationRuleForm.vue';
import AutomationRunTypeSelector from './components/AutomationRunTypeSelector.vue';
import AutomationWaitCondition from './components/AutomationWaitCondition.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: () => true }),
}));

vi.mock('dashboard/components-next/filter/operators', () => ({
  useOperators: () => ({ operators: { value: {} } }),
}));

const automationTypes = Object.fromEntries(
  [
    'conversation_created',
    'conversation_updated',
    'conversation_resolved',
    'message_created',
    'conversation_opened',
  ].map(event => [event, { conditions: [] }])
);

const triggerStub = {
  template: '<div />',
  methods: {
    resetValidation: vi.fn(),
    validate: vi.fn(() => true),
  },
};

const waitConditionStub = {
  props: [
    'isSavedWait',
    'hasError',
    'hasWindowError',
    'windowEnabled',
    'windowStart',
    'windowEnd',
  ],
  template: '<div />',
  methods: {
    resetValidation: vi.fn(),
    validate: vi.fn(() => true),
  },
};

const instantConditions = [
  {
    attribute_key: 'status',
    filter_operator: 'equal_to',
    values: 'open',
    query_operator: 'and',
    custom_attribute_type: '',
  },
];

const waitConditions = [
  {
    attribute_key: 'message_type',
    filter_operator: 'equal_to',
    values: 'outgoing',
    query_operator: 'and',
    custom_attribute_type: '',
  },
  {
    attribute_key: 'private_note',
    filter_operator: 'equal_to',
    values: false,
    query_operator: 'and',
    custom_attribute_type: '',
  },
  {
    attribute_key: 'priority',
    filter_operator: 'equal_to',
    values: 'high',
    query_operator: null,
    custom_attribute_type: '',
  },
];

const buildAutomation = ({ delayed = false } = {}) => ({
  name: 'Follow up',
  description: 'Follow up after a wait',
  event_name: delayed ? 'message_created' : 'conversation_created',
  execution_delay: delayed ? 60 : null,
  conditions: structuredClone(delayed ? waitConditions : instantConditions),
  actions: [{ action_name: 'assign_agent', action_params: [] }],
  files: [],
});

const panelOpen = vi.fn();

const mountComponent = ({ mode, automation }) =>
  shallowMount(AutomationRuleForm, {
    props: {
      mode,
      automation,
      automationTypes,
      getConditionDropdownValues: vi.fn(() => []),
      getActionDropdownValues: vi.fn(() => []),
      appendNewCondition: vi.fn(),
      appendNewAction: vi.fn(),
      removeFilter: vi.fn(),
      removeAction: vi.fn(),
      resetAction: vi.fn(),
      onEventChange: vi.fn(),
    },
    global: {
      stubs: {
        SidePanel: {
          template: '<div><slot /><slot name="footer" /></div>',
          methods: {
            open: panelOpen,
            close: vi.fn(),
          },
        },
        AutomationInstantTrigger: triggerStub,
        AutomationWaitCondition: waitConditionStub,
        WootInput: true,
      },
    },
  });

const selectRunType = async (wrapper, isDelayed) => {
  wrapper
    .findComponent(AutomationRunTypeSelector)
    .vm.$emit('update:modelValue', isDelayed);
  await nextTick();
};

describe('AutomationRuleForm', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('opens a rule whose conditions hold reactive dropdown options', async () => {
    const automation = buildAutomation();
    // Conditions hydrated from store-backed dropdowns (inboxes, agents, contacts) hold
    // reactive option objects rather than plain ones.
    automation.conditions[0].values = [reactive({ id: 1, name: 'Sales' })];
    const wrapper = mountComponent({ mode: 'edit', automation });

    wrapper.vm.open();
    await nextTick();

    expect(panelOpen).toHaveBeenCalled();
  });

  it('restores unsaved wait conditions after switching a new rule to instant and back', async () => {
    const automation = buildAutomation();
    const wrapper = mountComponent({ mode: 'create', automation });
    wrapper.vm.open();
    await nextTick();

    await selectRunType(wrapper, true);
    automation.event_name = 'message_created';
    automation.conditions = structuredClone(waitConditions);

    await selectRunType(wrapper, false);
    expect(automation.event_name).toBe('conversation_created');
    expect(automation.conditions).toEqual(instantConditions);

    await selectRunType(wrapper, true);
    expect(automation.event_name).toBe('message_created');
    expect(automation.conditions).toEqual(waitConditions);
    expect(
      wrapper.findComponent(AutomationWaitCondition).props('isSavedWait')
    ).toBe(true);
  });

  it('restores saved wait conditions after editing the instant draft', async () => {
    const automation = buildAutomation({ delayed: true });
    const wrapper = mountComponent({ mode: 'edit', automation });
    wrapper.vm.open(60);
    await nextTick();

    await selectRunType(wrapper, false);
    automation.event_name = 'conversation_created';
    automation.conditions = structuredClone(instantConditions);

    await selectRunType(wrapper, true);
    expect(automation.event_name).toBe('message_created');
    expect(automation.conditions).toEqual(waitConditions);
    expect(
      wrapper.findComponent(AutomationWaitCondition).props('isSavedWait')
    ).toBe(true);
  });

  it('hydrates the execution window and clears it for instant rules', async () => {
    const automation = buildAutomation({ delayed: true });
    const wrapper = mountComponent({ mode: 'edit', automation });
    wrapper.vm.open(60, 9 * 60, 18 * 60);
    await nextTick();

    expect(automation.execution_window_start_minutes).toBe(9 * 60);
    expect(automation.execution_window_end_minutes).toBe(18 * 60);

    await selectRunType(wrapper, false);
    expect(automation.execution_window_start_minutes).toBeNull();
    expect(automation.execution_window_end_minutes).toBeNull();
  });

  it('flags an invalid execution window and blocks saving', async () => {
    const automation = {
      ...buildAutomation({ delayed: true }),
      actions: [{ action_name: 'mute_conversation', action_params: [] }],
    };
    const wrapper = mountComponent({ mode: 'edit', automation });
    wrapper.vm.open(60, 18 * 60, 9 * 60);
    await nextTick();

    await wrapper.findAll('button')[1].trigger('click');

    expect(wrapper.emitted('save')).toBeUndefined();
    expect(
      wrapper.findComponent(AutomationWaitCondition).props('hasWindowError')
    ).toBe(true);
  });

  it('saves when the execution window is valid', async () => {
    const automation = {
      ...buildAutomation({ delayed: true }),
      conditions: [
        {
          attribute_key: 'message_type',
          filter_operator: 'equal_to',
          values: 'outgoing',
          query_operator: 'and',
          custom_attribute_type: '',
        },
        {
          attribute_key: 'priority',
          filter_operator: 'equal_to',
          values: 'high',
          query_operator: null,
          custom_attribute_type: '',
        },
      ],
      actions: [{ action_name: 'mute_conversation', action_params: [] }],
    };
    const wrapper = mountComponent({ mode: 'edit', automation });
    wrapper.vm.open(60, 9 * 60, 18 * 60);
    await nextTick();

    await wrapper.findAll('button')[1].trigger('click');

    expect(wrapper.emitted('save')).toHaveLength(1);
    expect(wrapper.emitted('save')[0][0]).toMatchObject({
      execution_window_start_minutes: 9 * 60,
      execution_window_end_minutes: 18 * 60,
    });
  });
});
