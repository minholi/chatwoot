require 'rails_helper'
require Rails.root.join 'spec/models/concerns/reauthorizable_shared.rb'

RSpec.describe AutomationRule do
  describe 'concerns' do
    it_behaves_like 'reauthorizable'
  end

  describe 'associations' do
    let(:account) { create(:account) }
    let(:params) do
      {
        name: 'Notify Conversation Created and mark priority query',
        description: 'Notify all administrator about conversation created and mark priority query',
        event_name: 'conversation_created',
        account_id: account.id,
        conditions: [
          {
            attribute_key: 'browser_language',
            filter_operator: 'equal_to',
            values: ['en'],
            query_operator: 'AND'
          },
          {
            attribute_key: 'country_code',
            filter_operator: 'equal_to',
            values: %w[USA UK],
            query_operator: nil
          }
        ],
        actions: [
          {
            action_name: :send_message,
            action_params: ['Welcome to the chatwoot platform.']
          },
          {
            action_name: :assign_team,
            action_params: [1]
          },
          {
            action_name: :remove_assigned_agent
          },
          {
            action_name: :remove_assigned_team
          },
          {
            action_name: :add_label,
            action_params: %w[support priority_customer]
          },
          {
            action_name: :assign_agent,
            action_params: [1]
          }
        ]
      }.with_indifferent_access
    end

    it 'returns valid record' do
      rule = FactoryBot.build(:automation_rule, params)
      expect(rule.valid?).to be true
    end

    it 'returns invalid record' do
      params[:conditions][0].delete('query_operator')
      rule = FactoryBot.build(:automation_rule, params)
      expect(rule.valid?).to be false
      expect(rule.errors.messages[:conditions]).to eq(['Automation conditions should have query operator.'])
    end

    it 'allows labels as a valid condition attribute' do
      params[:conditions] = [
        {
          attribute_key: 'labels',
          filter_operator: 'equal_to',
          values: ['bug'],
          query_operator: nil
        }
      ]
      rule = FactoryBot.build(:automation_rule, params)
      expect(rule.valid?).to be true
    end

    it 'validates label condition operators' do
      params[:conditions] = [
        {
          attribute_key: 'labels',
          filter_operator: 'is_present',
          values: [],
          query_operator: nil
        }
      ]
      rule = FactoryBot.build(:automation_rule, params)
      expect(rule.valid?).to be true
    end

    it 'allows private_note as a valid condition attribute' do
      params[:conditions] = [
        {
          attribute_key: 'private_note',
          filter_operator: 'equal_to',
          values: [true],
          query_operator: nil
        }
      ]
      rule = FactoryBot.build(:automation_rule, params)
      expect(rule.valid?).to be true
    end
  end

  describe 'reauthorizable' do
    context 'when prompt_reauthorization!' do
      it 'marks the rule inactive' do
        rule = create(:automation_rule)
        expect(rule.active).to be true
        rule.prompt_reauthorization!
        expect(rule.active).to be false
      end
    end

    context 'when reauthorization_required?' do
      it 'unsets the error count if conditions are updated' do
        rule = create(:automation_rule)
        rule.prompt_reauthorization!
        expect(rule.reauthorization_required?).to be true

        rule.update!(conditions: [{ attribute_key: 'browser_language', filter_operator: 'equal_to', values: ['en'], query_operator: 'AND' }])
        expect(rule.reauthorization_required?).to be false
      end

      it 'will not unset the error count if conditions are not updated' do
        rule = create(:automation_rule)
        rule.prompt_reauthorization!
        expect(rule.reauthorization_required?).to be true

        rule.update!(name: 'Updated name')
        expect(rule.reauthorization_required?).to be true
      end
    end
  end

  describe 'execution_delay validations' do
    let(:rule) { build(:automation_rule, account: create(:account)) }

    it 'allows nil (immediate execution)' do
      rule.execution_delay = nil
      expect(rule).to be_valid
    end

    it 'allows delays between 10 minutes and 30 days' do
      rule.execution_delay = 240
      expect(rule).to be_valid
    end

    it 'rejects delays below 10 minutes' do
      rule.execution_delay = 5
      expect(rule).not_to be_valid
      expect(rule.errors[:execution_delay]).to be_present
    end

    it 'rejects delays above 30 days' do
      rule.execution_delay = 43_201
      expect(rule).not_to be_valid
    end

    it 'rejects non-integer delays' do
      rule.execution_delay = 10.5
      expect(rule).not_to be_valid
    end

    it 'rejects a delay combined with an attribute_changed condition' do
      rule.execution_delay = 60
      rule.conditions = [{ 'attribute_key' => 'status', 'filter_operator' => 'attribute_changed',
                           'values' => { 'from' => ['open'], 'to' => ['pending'] }, 'query_operator' => nil }]
      expect(rule).not_to be_valid
      expect(rule.errors[:execution_delay]).to include('cannot be used with attribute_changed conditions.')
    end

    it 'allows a delayed message rule with a label condition' do
      rule.event_name = 'message_created'
      rule.execution_delay = 60
      rule.conditions = [{ 'attribute_key' => 'labels', 'filter_operator' => 'equal_to',
                           'values' => ['feature'], 'query_operator' => nil }]

      expect(rule).to be_valid
    end

    it 'rejects a delayed conversation-level rule with a label condition' do
      rule.event_name = 'conversation_updated'
      rule.execution_delay = 60
      rule.conditions = [{ 'attribute_key' => 'labels', 'filter_operator' => 'equal_to',
                           'values' => ['feature'], 'query_operator' => nil }]

      expect(rule).not_to be_valid
      expect(rule.errors[:execution_delay]).to include('only supports status and inbox conditions for conversation-level events.')
    end

    it 'rejects a delayed conversation-level rule with a mutable non-status condition' do
      rule.event_name = 'conversation_updated'
      rule.execution_delay = 60
      rule.conditions = [{ 'attribute_key' => 'priority', 'filter_operator' => 'equal_to', 'values' => ['urgent'], 'query_operator' => nil }]
      expect(rule).not_to be_valid
      expect(rule.errors[:execution_delay]).to include('only supports status and inbox conditions for conversation-level events.')
    end

    it 'allows a delayed conversation-level rule with only status conditions' do
      rule.event_name = 'conversation_updated'
      rule.execution_delay = 60
      rule.conditions = [{ 'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => ['pending'], 'query_operator' => nil }]
      expect(rule).to be_valid
    end

    it 'allows a delayed conversation_created rule (arms on creation)' do
      rule.event_name = 'conversation_created'
      rule.execution_delay = 10
      rule.conditions = [{ 'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => ['open'], 'query_operator' => nil }]
      expect(rule).to be_valid
    end

    it 'allows a delayed conversation-level rule scoped by status and inbox (immutable)' do
      rule.event_name = 'conversation_updated'
      rule.execution_delay = 60
      rule.conditions = [{ 'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => ['pending'], 'query_operator' => 'AND' },
                         { 'attribute_key' => 'inbox_id', 'filter_operator' => 'equal_to', 'values' => [1], 'query_operator' => nil }]
      expect(rule).to be_valid
    end

    it 'allows a delayed message_created rule with a non-status condition' do
      rule.event_name = 'message_created'
      rule.execution_delay = 60
      rule.conditions = [{ 'attribute_key' => 'message_type', 'filter_operator' => 'equal_to', 'values' => ['outgoing'], 'query_operator' => nil }]
      expect(rule).to be_valid
    end
  end

  describe 'execution_window validations' do
    let(:rule) { build(:automation_rule, account: create(:account), execution_delay: 60) }

    it 'allows nil (no window)' do
      expect(rule).to be_valid
    end

    it 'allows a same-day window' do
      rule.execution_window_start_minutes = 9 * 60
      rule.execution_window_end_minutes = 18 * 60
      expect(rule).to be_valid
    end

    it 'allows a window starting at midnight' do
      rule.execution_window_start_minutes = 0
      rule.execution_window_end_minutes = 6 * 60
      expect(rule).to be_valid
    end

    it 'rejects a window with only the start time' do
      rule.execution_window_start_minutes = 9 * 60
      expect(rule).not_to be_valid
      expect(rule.errors[:execution_window_start_minutes]).to include('must be set together with the end time.')
    end

    it 'rejects a window with only the end time' do
      rule.execution_window_end_minutes = 18 * 60
      expect(rule).not_to be_valid
      expect(rule.errors[:execution_window_start_minutes]).to include('must be set together with the end time.')
    end

    it 'rejects a window whose end is not after its start' do
      rule.execution_window_start_minutes = 18 * 60
      rule.execution_window_end_minutes = 9 * 60
      expect(rule).not_to be_valid
      expect(rule.errors[:execution_window_end_minutes]).to include('must be after the start time.')
    end

    it 'rejects an equal start and end' do
      rule.execution_window_start_minutes = 9 * 60
      rule.execution_window_end_minutes = 9 * 60
      expect(rule).not_to be_valid
      expect(rule.errors[:execution_window_end_minutes]).to include('must be after the start time.')
    end

    it 'rejects out-of-range minutes' do
      rule.execution_window_start_minutes = 1440
      rule.execution_window_end_minutes = 1500
      expect(rule).not_to be_valid
      expect(rule.errors[:execution_window_start_minutes]).to be_present
      expect(rule.errors[:execution_window_end_minutes]).to be_present
    end

    it 'rejects a window without an execution delay' do
      rule.execution_delay = nil
      rule.execution_window_start_minutes = 9 * 60
      rule.execution_window_end_minutes = 18 * 60
      expect(rule).not_to be_valid
      expect(rule.errors[:execution_window_start_minutes]).to include('can only be used with an execution delay.')
    end
  end

  describe 'execution window evaluation' do
    let(:rule) do
      build(:automation_rule, account: create(:account), execution_delay: 60,
                              execution_window_start_minutes: 9 * 60, execution_window_end_minutes: 18 * 60)
    end

    it 'allows any time when no window is set' do
      rule.execution_window_start_minutes = nil
      rule.execution_window_end_minutes = nil

      travel_to(Time.utc(2026, 9, 24, 3, 0)) do
        expect(rule.within_execution_window?('UTC')).to be true
      end
    end

    it 'accepts the start minute and rejects the end minute' do
      travel_to(Time.utc(2026, 9, 24, 9, 0)) do
        expect(rule.within_execution_window?('UTC')).to be true
      end
      travel_to(Time.utc(2026, 9, 24, 17, 59)) do
        expect(rule.within_execution_window?('UTC')).to be true
      end
      travel_to(Time.utc(2026, 9, 24, 18, 0)) do
        expect(rule.within_execution_window?('UTC')).to be false
      end
    end

    it 'evaluates the window in the given timezone' do
      # 12:30 UTC is 09:30 in São Paulo, inside the 09:00-18:00 window.
      travel_to(Time.utc(2026, 9, 24, 12, 30)) do
        expect(rule.within_execution_window?('America/Sao_Paulo')).to be true
      end
    end

    it 'returns the same day opening when it is still ahead' do
      travel_to(Time.utc(2026, 9, 24, 6, 0)) do
        expect(rule.next_execution_window_start('UTC')).to eq(Time.utc(2026, 9, 24, 9, 0))
      end
    end

    it 'returns the next day opening when the window already closed' do
      travel_to(Time.utc(2026, 9, 24, 20, 0)) do
        expect(rule.next_execution_window_start('UTC')).to eq(Time.utc(2026, 9, 25, 9, 0))
      end
    end

    it 'shifts an opening that falls in the spring-forward gap to the next valid time' do
      rule.execution_window_start_minutes = (2 * 60) + 30
      # 05:00 UTC is midnight in New York on the 2026 spring-forward day (02:00-03:00 is skipped).
      travel_to(Time.utc(2026, 3, 8, 5, 0)) do
        expect(rule.next_execution_window_start('America/New_York')).to eq(Time.utc(2026, 3, 8, 7, 30))
      end
    end
  end

  describe 'discarding stale pending executions on edit' do
    let(:account) { create(:account) }
    let(:conversation) { create(:conversation, account: account, status: :pending) }
    let(:status_condition) { { 'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => ['pending'], 'query_operator' => nil } }
    let(:rule) do
      create(:automation_rule, account: account, event_name: 'conversation_updated', execution_delay: 60,
                               conditions: [status_condition], actions: [{ 'action_name' => 'add_label', 'action_params' => ['stale'] }])
    end

    before { AutomationRulePendingExecution.schedule(rule: rule, conversation: conversation) }

    it 'discards armed rows when the actions change' do
      rule.update!(actions: [{ 'action_name' => 'add_label', 'action_params' => ['urgent'] }])
      expect(rule.pending_executions.pending).to be_empty
    end

    it 'discards armed rows when the delay changes' do
      rule.update!(execution_delay: 120)
      expect(rule.pending_executions.pending).to be_empty
    end

    it 'discards armed rows when the execution window changes' do
      rule.update!(execution_window_start_minutes: 9 * 60, execution_window_end_minutes: 18 * 60)
      expect(rule.pending_executions.pending).to be_empty
    end

    it 'discards armed rows when the rule is deactivated, so reactivating cannot resurrect them' do
      rule.update!(active: false)
      expect(rule.pending_executions.armed).to be_empty

      rule.update!(active: true)
      expect(rule.pending_executions.armed).to be_empty
    end

    it 'discards a stale processing row that the sweep would otherwise reclaim' do
      rule.pending_executions.first.update!(status: :processing)
      rule.update!(actions: [{ 'action_name' => 'add_label', 'action_params' => ['urgent'] }])
      expect(rule.pending_executions.armed).to be_empty
    end

    it 'leaves an executing row alone because its actions are already in flight' do
      rule.pending_executions.first.update!(status: :executing)
      rule.update!(actions: [{ 'action_name' => 'add_label', 'action_params' => ['urgent'] }])
      expect(rule.pending_executions.executing.count).to eq(1)
    end

    it 'frees the episode slot so the new definition re-arms for the same episode' do
      rule.update!(actions: [{ 'action_name' => 'add_label', 'action_params' => ['urgent'] }])
      AutomationRulePendingExecution.schedule(rule: rule, conversation: conversation)
      expect(rule.pending_executions.pending.count).to eq(1)
    end

    it 'leaves armed rows untouched on a name-only edit' do
      rule.update!(name: 'Renamed rule')
      expect(rule.pending_executions.pending.count).to eq(1)
    end
  end
end
