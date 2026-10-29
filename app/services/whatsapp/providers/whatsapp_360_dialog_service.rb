class Whatsapp::Providers::Whatsapp360DialogService < Whatsapp::Providers::BaseService
  def send_message(phone_number, message)
    @message = message
    if message.attachments.present?
      send_attachment_message(phone_number, message)
    elsif message.content_type == 'input_select'
      send_interactive_text_message(phone_number, message)
    else
      send_text_message(phone_number, message)
    end
  end

  # Marketing templates go through the Marketing Messages Lite API. Accounts not onboarded to it
  # fall back to the regular /messages delivery because of the cloud_api_fallback policy.
  def send_template(phone_number, template_info, message)
    body = { messaging_product: 'whatsapp', to: phone_number, template: template_body_parameters(template_info), type: 'template' }
    endpoint = 'messages'
    if marketing_template?(template_info)
      endpoint = 'marketing_messages'
      body[:product_policy] = 'cloud_api_fallback'
    end

    response = HTTParty.post("#{api_base_path}/#{endpoint}", headers: api_headers, body: body.to_json)

    process_response(response, message)
  end

  def sync_templates
    # ensuring that channels with wrong provider config wouldn't keep trying to sync templates
    whatsapp_channel.mark_message_templates_updated
    response = HTTParty.get("#{api_base_path}/v1/configs/templates", headers: api_headers)
    whatsapp_channel.update(message_templates: response['waba_templates'], message_templates_last_updated: Time.now.utc) if response.success?
  end

  def validate_provider_config?
    response = HTTParty.post(
      "#{api_base_path}/v1/configs/webhook",
      headers: { 'D360-API-KEY': whatsapp_channel.provider_config['api_key'], 'Content-Type': 'application/json' },
      body: {
        url: "#{ENV.fetch('FRONTEND_URL', nil)}/webhooks/whatsapp/#{whatsapp_channel.phone_number}"
      }.to_json
    )
    response.success?
  end

  def api_headers
    { 'D360-API-KEY' => whatsapp_channel.provider_config['api_key'], 'Content-Type' => 'application/json' }
  end

  def media_url(media_id, phone_number_id = nil)
    "#{api_base_path}/#{media_id}"
  end

  def create_csat_template(template_config)
    csat_template_service.create_template(template_config)
  end

  def delete_csat_template(template_name = nil)
    csat_template_service.delete_template(template_name)
  end

  def get_template_status(template_name)
    csat_template_service.get_template_status(template_name)
  end

  def api_base_path
    # provide the environment variable when testing against sandbox : 'https://waba-sandbox.360dialog.io/v1'
    ENV.fetch('360DIALOG_BASE_URL', 'https://waba-v2.360dialog.io')
  end

  private

  def csat_template_service
    @csat_template_service ||= Whatsapp::Csat360DialogTemplateService.new(whatsapp_channel)
  end

  def send_text_message(phone_number, message)
    response = HTTParty.post(
      "#{api_base_path}/messages",
      headers: api_headers,
      body: {
        messaging_product: 'whatsapp',
        context: whatsapp_reply_context(message),
        to: phone_number,
        text: { body: message.outgoing_content },
        type: 'text'
      }.to_json
    )

    process_response(response, message)
  end

  def send_attachment_message(phone_number, message)
    attachment = message.attachments.first
    type = %w[image audio video].include?(attachment.file_type) ? attachment.file_type : 'document'
    type_content = {
      'link': attachment.download_url
    }
    type_content['caption'] = message.outgoing_content unless %w[audio sticker].include?(type)
    type_content['filename'] = attachment.file.filename if type == 'document'

    response = HTTParty.post(
      "#{api_base_path}/messages",
      headers: api_headers,
      body: {
        'messaging_product' => 'whatsapp',
        'context' => whatsapp_reply_context(message),
        'to' => phone_number,
        'type' => type,
        type.to_s => type_content
      }.to_json
    )

    process_response(response, message)
  end

  def error_message(response)
    # {"meta": {"success": false, "http_code": 400, "developer_message": "errro-message", "360dialog_trace_id": "someid"}}
    response.parsed_response.dig('meta', 'developer_message')
  end

  def template_body_parameters(template_info)
    {
      name: template_info[:name],
      namespace: template_info[:namespace],
      language: {
        policy: 'deterministic',
        code: template_info[:lang_code]
      },
      components: template_info[:parameters]
    }.compact
  end

  def marketing_template?(template_info)
    whatsapp_channel.message_templates&.any? do |template|
      template['name'] == template_info[:name] &&
        template['language']&.downcase == template_info[:lang_code]&.downcase &&
        template['category'] == 'MARKETING'
    end
  end

  def whatsapp_reply_context(message)
    reply_to = message.content_attributes[:in_reply_to_external_id]
    return nil if reply_to.blank?

    {
      message_id: reply_to
    }
  end

  def send_interactive_text_message(phone_number, message)
    payload = create_payload_based_on_items(message)

    response = HTTParty.post(
      "#{api_base_path}/messages",
      headers: api_headers,
      body: {
        messaging_product: 'whatsapp',
        to: phone_number,
        interactive: payload,
        type: 'interactive'
      }.to_json
    )

    process_response(response, message)
  end
end

Whatsapp::Providers::Whatsapp360DialogService.prepend_mod_with('Whatsapp::Providers::Whatsapp360DialogService')
