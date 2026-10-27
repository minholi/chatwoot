class Whatsapp::Csat360DialogTemplateService < Whatsapp::CsatTemplateService
  def delete_template(template_name = nil)
    template_name ||= CsatTemplateNameService.csat_template_name(@whatsapp_channel.inbox.id)
    response = HTTParty.delete("#{templates_path}/#{template_name}", headers: api_headers)
    { success: response.success?, response_body: response.body }
  end

  def get_template_status(template_name)
    response = HTTParty.get(templates_path, headers: api_headers, query: { filters: { 'business_templates.name' => template_name }.to_json })
    template_data = response.success? && response['waba_templates']&.find { |template| template['name'] == template_name }
    return { success: false, error: 'Template not found' } unless template_data

    {
      success: true,
      template: {
        id: template_data['external_id'], name: template_data['name'],
        status: template_data['status'].to_s.upcase, language: template_data['language']
      }
    }
  end

  private

  def send_template_creation_request(request_body)
    HTTParty.post(templates_path, headers: api_headers, body: request_body.to_json)
  end

  def templates_path
    "#{api_base_path}/v1/configs/templates"
  end

  def api_headers
    @whatsapp_channel.provider_service.api_headers
  end

  def api_base_path
    @whatsapp_channel.provider_service.api_base_path
  end
end
