# frozen_string_literal: true

#   Copyright (c) 2010-2012, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

class ApplicationController < ActionController::Base
  before_action :force_tablet_html
  has_mobile_fu

  rescue_from ActionController::InvalidAuthenticityToken do
    if user_signed_in?
      logger.warn "#{current_user.diaspora_handle} CSRF token fail. referer: #{request.referer || 'empty'}"
      Workers::Mail::CsrfTokenFail.perform_async(current_user.id)
      sign_out current_user
    end
    flash[:error] = I18n.t("error_messages.csrf_token_fail")
    redirect_to new_user_session_path format: request[:format]
  end

  before_action :ensure_http_referer_is_set
  before_action :set_locale
  before_action :set_diaspora_header
  before_action :mobile_switch
  before_action :gon_set_current_user
  before_action :gon_set_appconfig
  before_action :gon_set_preloads
  before_action :configure_permitted_parameters, if: :devise_controller?

  before_action :set_ddn_cookie

  helper_method :all_aspects,
                :all_contacts_count,
                :my_contacts_count,
                :only_sharing_count,
                :tag_followings,
                :tags,
                :open_publisher

  layout proc { request.format == :mobile ? "application" : "with_header_with_footer" }

  private

  def default_serializer_options
    {root: false}
  end

  def ensure_http_referer_is_set
    request.env["HTTP_REFERER"] ||= "/"
  end

  # Overwriting the sign_out redirect path method
  def after_sign_out_path_for(resource_or_scope)
    is_mobile_device? ? root_path : new_user_session_path
  end

  def all_aspects
    @all_aspects ||= current_user.aspects
  end

  def all_contacts_count
    @all_contacts_count ||= current_user.contacts.count
  end

  def my_contacts_count
    @my_contacts_count ||= current_user.contacts.receiving.count
  end

  def only_sharing_count
    @only_sharing_count ||= current_user.contacts.only_sharing.count
  end

  def tags
    @tags ||= current_user.followed_tags
  end

  def ensure_page
    params[:page] = params[:page] ? params[:page].to_i : 1
  end

  def set_diaspora_header
    headers["X-Diaspora-Version"] = AppConfig.version_string

    if AppConfig.git_available?
      headers["X-Git-Update"] = AppConfig.git_update if AppConfig.git_update.present?
      headers["X-Git-Revision"] = AppConfig.git_revision if AppConfig.git_revision.present?
    end
  end

  def set_locale
    if user_signed_in?
      I18n.locale = current_user.language
    else
      locale = http_accept_language.language_region_compatible_from AVAILABLE_LANGUAGE_CODES
      locale ||= DEFAULT_LANGUAGE
      I18n.locale = locale
    end
  end

  def redirect_unless_admin
    return if current_user.admin?
    redirect_to stream_url, notice: "you need to be an admin to do that"
  end

  def redirect_unless_moderator
    return if current_user.moderator?
    redirect_to stream_url, notice: "you need to be an admin or moderator to do that"
  end

  # use :mobile view for mobile and :html for everything else
  # (except if explicitly specified, e.g. :json, :xml)
  def mobile_switch
    if session[:mobile_view] == true && request.format.html?
      request.format = :mobile
    end
  end

  def force_tablet_html
    session[:tablet_view] = false
  end

  def after_sign_in_path_for(resource)
    stored_location_for(:user) || current_user_redirect_path
  end

  def max_time
    params[:max_time] ? Time.at(params[:max_time].to_i) : Time.now + 1
  end

  def current_user_redirect_path
    # If getting started is active AND the user has not completed the getting_started page
    if current_user.getting_started? && !current_user.basic_profile_present?
      getting_started_path
    else
      stream_path
    end
  end

  def gon_set_appconfig
    gon.push(appConfig: {
               settings: {podname: AppConfig.settings.pod_name},
               map:      {mapbox: {
                 enabled:      AppConfig.map.mapbox.enabled?,
                 access_token: AppConfig.map.mapbox.access_token,
                 style:        AppConfig.map.mapbox.style
               }}
             })
  end

  def gon_set_current_user
    return unless user_signed_in?
    a_ids = session[:a_ids] || []
    user = UserPresenter.new(current_user, a_ids)
    gon.push(user: user)
  end

  def gon_set_preloads
    return unless gon.preloads.nil?
    gon.preloads = {}
  end

  def set_ddn_cookie
    return unless user_signed_in?

    cookie_payload = {
      expires:  1.hour.from_now.to_i,
      username: current_user.username
    }.to_json

    iv = Random.new.bytes 16

    cipher = OpenSSL::Cipher.new("AES-256-CBC")
    cipher.encrypt
    cipher.key = Digest::SHA256.new.update(Diaspora::Application.config.ddn_key).digest
    cipher.iv = iv

    enc_payload = Base64.encode64(cipher.update(cookie_payload) + cipher.final).strip

    cookies[:ddn_key] = {
      domain: Diaspora::Application.config.ddn_cookie_domain,
      value:  "#{enc_payload}|#{Base64.encode64(iv).strip}"
    }
  end

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_in, keys: [:otp_attempt])
  end
end
