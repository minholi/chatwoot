require 'rails_helper'

RSpec.describe 'WhatsApp campaign on a 360dialog inbox', type: :request do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'default', phone_number: '+5541933334444',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:label) { create(:label, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5541988887777') }
  let(:campaign) do
    create(:campaign, account: account, inbox: channel.inbox, audience: [{ type: 'Label', id: label.id }],
                      template_params: {
                        'name' => 'ticket_status_updated',
                        'namespace' => '23423423_2342423_324234234_2343224',
                        'category' => 'UTILITY',
                        'language' => 'en',
                        'processed_params' => { 'body' => { 'name' => 'John', 'ticket_id' => '2332' } }
                      })
  end
  let(:recipient) { campaign.campaign_recipients.find_by!(contact: contact) }
  let!(:send_request) do
    stub_request(:post, 'https://waba-v2.360dialog.io/messages')
      .with(
        headers: { 'D360-API-KEY' => 'test_key' },
        body: {
          messaging_product: 'whatsapp',
          to: '+5541988887777',
          template: {
            name: 'ticket_status_updated',
            namespace: '23423423_2342423_324234234_2343224',
            language: { policy: 'deterministic', code: 'en' },
            components: [{
              type: 'body',
              parameters: [
                { type: 'text', parameter_name: 'name', text: 'John' },
                { type: 'text', parameter_name: 'ticket_id', text: '2332' }
              ]
            }]
          },
          type: 'template'
        }.to_json
      )
      .to_return(status: 200, body: { messages: [{ id: 'wamid.campaign-360dialog' }] }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  before do
    account.enable_features!(:campaigns)
    contact.update_labels([label.title])
    perform_enqueued_jobs { campaign.trigger! }
  end

  # 360dialog v2 forwards Cloud API webhooks to the URL registered for the channel
  def post_status_webhook(status)
    payload = {
      object: 'whatsapp_business_account',
      entry: [{
        id: 'waba-id',
        changes: [{
          field: 'messages',
          value: {
            messaging_product: 'whatsapp',
            metadata: { display_phone_number: '5541933334444', phone_number_id: '360dialog-phone-id' },
            statuses: [{ id: 'wamid.campaign-360dialog', recipient_id: '5541988887777' }.merge(status)]
          }
        }]
      }]
    }

    perform_enqueued_jobs do
      post "/webhooks/whatsapp/#{channel.phone_number}", params: payload.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
    end
    expect(response).to have_http_status(:ok)
  end

  it 'sends the template and marks the recipient as sent with the 360dialog message id' do
    expect(send_request).to have_been_requested.once
    expect(campaign.reload).to be_completed
    expect(recipient).to be_sent
    expect(recipient.source_id).to eq('wamid.campaign-360dialog')
  end

  it 'tracks delivered and read callbacks from 360dialog' do
    post_status_webhook(status: 'delivered', timestamp: '1761750000')
    expect(recipient.reload).to be_delivered
    expect(recipient.delivered_at).to eq(Time.zone.at(1_761_750_000))

    post_status_webhook(status: 'read', timestamp: '1761750060')
    expect(recipient.reload).to be_read
    expect(recipient.read_at).to eq(Time.zone.at(1_761_750_060))
  end

  it 'records the error of a failed callback from 360dialog' do
    post_status_webhook(
      status: 'failed', timestamp: '1761750000',
      errors: [{ code: 131_049, title: 'This message was not delivered to maintain healthy ecosystem engagement.',
                 error_data: { details: 'In order to maintain a healthy ecosystem engagement, the message failed to be delivered.' } }]
    )

    recipient.reload
    expect(recipient).to be_failed
    expect(recipient.error_code).to eq('131049')
    expect(recipient.error_message).to eq('In order to maintain a healthy ecosystem engagement, the message failed to be delivered.')
  end
end
