require 'rails_helper'

RSpec.describe ConversationJourneyHandler do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'conversation created in an inbox without bot' do
    it 'enters the human queue on creation' do
      conversation = create(:conversation, account: account, inbox: inbox)

      expect(conversation.started_at).to be_within(1.second).of(conversation.created_at)
      expect(conversation.opened_at).to be_nil
      expect(conversation.closed_at).to be_nil
    end

    it 'marks the assignment at the same time when created with an assignee' do
      conversation = create(:conversation, account: account, inbox: inbox, assignee: agent)

      expect(conversation.opened_at).to eq(conversation.started_at)
    end

    it 'marks the assignment when an agent is assigned later' do
      conversation = create(:conversation, account: account, inbox: inbox)

      travel_to(5.minutes.from_now) do
        conversation.update!(assignee: agent)
        expect(conversation.reload.opened_at).to be_within(1.second).of(Time.current)
      end
    end

    it 'keeps the first assignment when the conversation is reassigned' do
      conversation = create(:conversation, account: account, inbox: inbox, assignee: agent)
      opened_at = conversation.opened_at

      travel_to(5.minutes.from_now) do
        conversation.update!(assignee: create(:user, account: account, role: :agent))
      end

      expect(conversation.reload.opened_at).to be_within(1.second).of(opened_at)
    end
  end

  describe 'conversation handled by a bot' do
    let(:conversation) do
      create(:agent_bot_inbox, inbox: inbox)
      create(:conversation, account: account, inbox: inbox)
    end

    before { allow(Rails.configuration.dispatcher).to receive(:dispatch) }

    it 'has no journey while pending with the bot' do
      expect(conversation.status).to eq('pending')
      expect(conversation.started_at).to be_nil
    end

    it 'enters the queue on bot handoff without assignment' do
      travel_to(10.minutes.from_now) do
        conversation.bot_handoff!
        expect(conversation.reload.started_at).to be_within(1.second).of(Time.current)
      end
      expect(conversation.opened_at).to be_nil
    end

    it 'uses the handoff time as assignment when an agent was already assigned' do
      conversation.update!(assignee: agent)
      expect(conversation.reload.status).to eq('pending')

      conversation.bot_handoff!

      expect(conversation.reload.opened_at).to eq(conversation.started_at)
    end

    it 'ignores assignment to the AI assistant' do
      conversation.bot_handoff!
      conversation.update!(ai_assignee: create(:agent_bot, account: account))

      expect(conversation.reload.opened_at).to be_nil
    end
  end

  describe 'resolution and reopening' do
    let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: agent) }

    it 'sets closed_at on resolve and keeps it on later updates' do
      conversation.resolved!
      closed_at = conversation.reload.closed_at

      travel_to(1.hour.from_now) do
        conversation.update!(label_list: ['lead'], custom_attributes: { 'curso' => 'Direito' })
      end

      expect(closed_at).to be_present
      expect(conversation.reload.closed_at).to be_within(1.second).of(closed_at)
    end

    it 'starts a new cycle when a resolved conversation is reopened' do
      conversation.resolved!

      travel_to(1.day.from_now) do
        conversation.open!
        conversation.reload

        expect(conversation.closed_at).to be_nil
        expect(conversation.human_first_reply_at).to be_nil
        expect(conversation.started_at).to be_within(1.second).of(Time.current)
        expect(conversation.opened_at).to eq(conversation.started_at)
      end
    end

    it 'keeps the cycle when a snoozed conversation is reopened' do
      started_at = conversation.started_at
      conversation.snoozed!

      travel_to(1.hour.from_now) { conversation.open! }

      expect(conversation.reload.started_at).to be_within(1.second).of(started_at)
    end

    it 'resets the journey when the conversation goes back to the bot' do
      conversation.pending!

      expect(conversation.reload.started_at).to be_nil
      expect(conversation.opened_at).to be_nil
    end
  end

  describe 'human first reply' do
    let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: agent) }

    it 'records the first public human reply after entering the queue' do
      message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: agent)

      expect(conversation.reload.human_first_reply_at).to be_within(1.second).of(message.created_at)
    end

    it 'does not overwrite with later replies' do
      first = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: agent)
      travel_to(10.minutes.from_now) do
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: agent)
      end

      expect(conversation.reload.human_first_reply_at).to be_within(1.second).of(first.created_at)
    end

    it 'ignores private notes, bot messages and incoming messages' do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: agent, private: true)
      create(:message, :bot_message, account: account, inbox: inbox, conversation: conversation)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)

      expect(conversation.reload.human_first_reply_at).to be_nil
    end

    it 'does not record a reply sent while the conversation is with the bot' do
      create(:agent_bot_inbox, inbox: inbox)
      bot_conversation = create(:conversation, account: account, inbox: inbox)

      create(:message, account: account, inbox: inbox, conversation: bot_conversation, message_type: :outgoing, sender: agent)

      expect(bot_conversation.reload.human_first_reply_at).to be_nil
    end

    it 'does not dispatch an extra conversation updated event' do
      conversation
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: agent)

      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
        .with(Conversation::CONVERSATION_UPDATED, anything, hash_including(changed_attributes: hash_including('human_first_reply_at')))
    end
  end
end
