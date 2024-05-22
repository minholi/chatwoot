# https://docs.360dialog.com/whatsapp-api/whatsapp-api/media
# https://developers.facebook.com/docs/whatsapp/api/media/

class Whatsapp::IncomingMessageWhatsappCloudService < Whatsapp::IncomingMessageBaseService
  private

  def processed_params
    @processed_params ||= params[:entry].try(:first).try(:[], 'changes').try(:first).try(:[], 'value')
  end

  def download_attachment_file(attachment_payload)
    url_response = HTTParty.get(inbox.channel.media_url(attachment_payload[:id]), headers: inbox.channel.api_headers)
    download_url = url_response.parsed_response['url']
    # Changes media download url as described in https://docs.360dialog.com/docs/waba-messaging/media/upload-retrieve-or-delete-media#retrieve-media-url
    download_url.gsub!('https://lookaside.fbsbx.com', 'https://waba-v2.360dialog.io')
    # This url response will be failure if the access token has expired.
    inbox.channel.authorization_error! if url_response.unauthorized?
    Down.download(download_url, headers: inbox.channel.api_headers) if url_response.success?
  end
end
