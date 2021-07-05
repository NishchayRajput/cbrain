
#
# CBRAIN Project
#
# Copyright (C) 2008-2012
# The Royal Institution for the Advancement of Learning
# McGill University
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

require 'ipaddr'
require 'http_user_agent'

# Sesssions controller for the BrainPortal interface
# This controller handles the login/logout function of the site.
#
# Original author: restful_authentication plugin
# Modified by: Tarek Sherif
class SessionsController < ApplicationController

  Revision_info=CbrainFileRevision[__FILE__] #:nodoc:

  include GlobusHelpers

  api_available :only => [ :new, :show, :create, :destroy ]

  before_action      :user_already_logged_in,    :only => [ :new, :create, :globus ]
  skip_before_action :verify_authenticity_token, :only => [ :create ] # we invoke it ourselves in create()

  def new #:nodoc:
    reqenv           = request.env
    rawua            = reqenv['HTTP_USER_AGENT'] || 'unknown/unknown'
    ua               = HttpUserAgent.new(rawua)
    @browser_name    = ua.browser_name    || "(unknown browser name)"
    @browser_version = ua.browser_version || "(unknown browser version)"

    @globus_uri      = globus_login_uri # can be nil

    respond_to do |format|
      format.html
      format.any { head :unauthorized }
    end
  end

  def create #:nodoc:
    if ! api_request? # JSON is used for API calls; XML not yet fully supported
      verify_authenticity_token  # from Rails; will raise exception if not present.
    end
    user = User.authenticate(params[:login], params[:password]) # can be nil if it fails
    all_ok = create_from_user(user, 'CBRAIN')

    if ! all_ok
      auth_failed()
      return
    end

    # Record that the user connected using the CBRAIN login page
    cbrain_session[:login_page] = 'CBRAIN'

    respond_to do |format|
      format.html { redirect_back_or_default(start_page_path) }
      format.json { render :json => json_session_info, :status => 200 }
      format.xml  { render :xml  =>  xml_session_info, :status => 200 }
    end
  end

  def show #:nodoc:
    if current_user
      respond_to do |format|
        format.html { head   :ok                                                         }
        format.xml  { render :xml  =>  xml_session_info, :status => 200 }
        format.json { render :json => json_session_info, :status => 200 }
      end
    else
      head :unauthorized
    end
  end

  def destroy #:nodoc:
    unless current_user
      respond_to do |format|
        format.html { redirect_to new_session_path }
        format.xml  { head :unauthorized }
        format.json { head :unauthorized }
      end
      return
    end

    if current_user
      portal = BrainPortal.current_resource
      current_user.addlog("Logged out") if current_user
      portal.addlog("User #{current_user.login} logged out") if current_user
    end

    if cbrain_session
      cbrain_session.deactivate
      cbrain_session.clear
    end

    reset_session # Rails

    respond_to do |format|
      format.html {
                    flash[:notice] = "You have been logged out."
                    redirect_to new_session_path
                  }
      format.xml  { head :ok }
      format.json { head :ok }
    end
  end

  # This action receives a JSON authentication
  # request from globus and uses it to verify a user's
  # identity, logging in the user if all is ok.
  def globus
    code  = params[:code].presence.try(:strip)
    state = params[:state].presence || 'wrong'

    # Some initial simple validations
    if !code || state != globus_current_state()
      cb_error "Globus session is out of sync with CBRAIN"
    end

    # Query Globus; this returns all the info we need at the same time.
    identity_struct = globus_fetch_token(code)
    if !identity_struct
      cb_error "Could not fetch your identity information from Globus"
    end
    Rails.logger.info "Globus identity struct:\n#{identity_struct.pretty_inspect.strip}"

    # Globus has a security bug with ORCID, we reject those; TODO remove once they fix
    # this, and adjust the map() below to remove the if-end block
    rejected_providers = [ 'ORCID' ]

    # Fetch emails; globus returns a standard record, but with additional
    # identities under 'identity_set'; we kind of flatten this and extract all emails.
    identity_set  = [] + (identity_struct["identity_set"] || [])
    identity_set << identity_struct if identity_set.empty? # the full struct, even with the identity_set still in
    emails = identity_set.map do |record|
      provider_name = record['identity_provider_display_name'] # TODO (see above)
      if rejected_providers.include? provider_name
        Rails.logger.warn "Ignored Globus ORCID identity for #{record['email']}"
        next nil
      end
      record["email"]
    end
    emails.compact!

    # Check email against user list
    if emails.empty?
      cb_error "No provider email addresses are found in your Globus identities. Sorry. (Note: ORCID identities are not supported)"
    end

    # Match emails and log in.
    login_with_globus_emails(emails)

  rescue CbrainException => ex
    flash[:error] = "#{ex.message}" if ex.is_a?(CbrainException)
    redirect_to new_session_path
  rescue => ex
    clean_bt = Rails.backtrace_cleaner.clean(ex.backtrace || [])
    Rails.logger.error "Globus auth failed: #{ex.class} #{ex.message} at #{clean_bt[0]}"
    flash[:error] = 'The Globus authentication failed'
    redirect_to new_session_path
  end

  ###############################################
  #
  # Private methods
  #
  ###############################################

  private

  def user_already_logged_in #:nodoc:
    if current_user
      respond_to do |format|
        format.html { redirect_to start_page_path }
        format.json { render :json => json_session_info, :status => 200 }
        format.xml  { render :xml  =>  xml_session_info, :status => 200 }
      end
    end
  end

  # Does all sort of housekeeping and checks when +user+ logs in.
  # If user is nil, tells the framework the authentication has failed.
  # +origin+ is a keyword describing the origin of the authentication
  # for the user.
  def create_from_user(user, origin='CBRAIN') #:nodoc:

    # Bad login/password?
    unless user
      flash.now[:error] = 'Invalid user name or password.'
      Kernel.sleep 3 # Annoying, as it blocks the instance for other users too. Sigh.
      return false
    end

    # Not in IP whitelist?
    whitelist = (user.meta[:ip_whitelist] || '')
      .split(',')
      .map { |ip| IPAddr.new(ip.strip) rescue nil }
      .reject(&:blank?)
    if whitelist.present? && ! whitelist.any? { |ip| ip.include? cbrain_request_remote_ip }
      flash.now[:error] = 'Untrusted source IP address.'
      return false
    end

    # Check if the user or the portal is locked
    portal = BrainPortal.current_resource
    locked_message  = portal_or_account_locked?(portal,user)
    if locked_message.present?
      flash[:error] = locked_message
      return false
    end

    # Everything OK
    self.current_user = user # this ALSO ACTIVATES THE SESSION
    session[:user_id] = user.id  if request.format.to_sym == :html
    user_tracking(portal, origin) # Figures out IP address, user agent, etc, once.

    return true

  end

  # Send a proper HTTP error code
  # when a user has not properly authenticated
  def auth_failed
    respond_to do |format|
      format.html { render :action => 'new', :status => :ok } # should it be :unauthorized ?
      format.json { head   :unauthorized }
      format.xml  { head   :unauthorized }
    end
  end

  def portal_or_account_locked?(portal,user) #:nodoc:

    # Portal locked?
    if portal.portal_locked? && !user.has_role?(:admin_user)
      return "The system is currently locked. Please try again later."
    end

    # Account locked?
    if user.account_locked?
      return "This account is locked, please write to #{User.admin.email.presence || "the support staff"} to get this account unlocked."
    end

    return ""
  end

  def user_tracking(portal,origin='CBRAIN') #:nodoc:
    user   = current_user
    cbrain_session.activate(user.id)

    # Record the best guess for browser's remote host IP and name
    reqenv      = request.env
    from_ip     = cbrain_request_remote_ip rescue nil
    from_host   = hostname_from_ip(from_ip)
    from_ip   ||= '0.0.0.0'
    from_host ||= 'unknown'
    cbrain_session[:guessed_remote_ip]   = from_ip
    cbrain_session[:guessed_remote_host] = from_host
    cbrain_session.remote_resource_id    = portal.id # for general navigation help

    # Record the user agent
    raw_agent = reqenv['HTTP_USER_AGENT'] || 'unknown/unknown'
    cbrain_session[:raw_user_agent]      = raw_agent

    # Record that the user logged in
    parsed         = HttpUserAgent.new(raw_agent)
    browser        = (parsed.browser_name    || 'unknown browser')
    brow_ver       = (parsed.browser_version || '?')
    os             = (parsed.os_name         || 'unknown OS')
    pretty_brow    = "#{browser} #{brow_ver} on #{os}"
    pretty_host    = "#{from_ip}"
    if (from_host != 'unknown' && from_host != from_ip)
       pretty_host = "#{from_host} (#{pretty_host})"
    end

    # The authentication_mechanism is a string which describes
    # the mechanism that was used by the user to log in.
    authentication_mechanism = "password" # in future this could change

    # In case of logins though the API, record that in the session too.
    if api_request?
      cbrain_session[:api] = 'yes'
      authentication_mechanism = 'password/api'
    end

    # The following two log lines differ at their beginning but provides
    # the same information afterwards. Thus the weird style alignment.
    user.addlog(      "Logged in on #{portal.name}/#{origin} with #{authentication_mechanism} from #{pretty_host} using #{pretty_brow}")
    portal.addlog("User #{user.login} logged in on #{origin} with #{authentication_mechanism} from #{pretty_host} using #{pretty_brow}")
    user.update_attribute(:last_connected_at, Time.now)

    # Admin users start with some differences in behavior
    if user.has_role?(:admin_user)
      cbrain_session[:active_group_id] = "all"
    end
  end

  # Given a list of emails, find a single user that match them
  # and proceed to activate the session for that user.
  def login_with_globus_emails(emails)

    # Find the users that have these emails. Hopefully, only one.
    users = User.where(:email => emails)

    if users.size == 0
      flash[:error] = "No CBRAIN user matches your Globus email addresses. Create a CBRAIN account or set your existing CBRAIN account email to your Globus provider's email."
      Rails.logger.info "GLOBUS warning: no CBRAIN accounts found for emails: #{emails.join(", ")}"
      redirect_to new_session_path
      return
    end

    if users.size > 1
      flash[:notice] = "Several CBRAIN user accounts match your Globus email addresses. Please contact the CBRAIN admins."
      Rails.logger.info "GLOBUS error: multiple CBRAIN accounts found for emails: #{emails.join(", ")}"
      redirect_to new_session_path
      return
    end

    # The one lucky user
    user = users.first

    # Login the user
    all_ok = create_from_user(user, 'CBRAIN/Globus')

    if ! all_ok
      redirect_to new_session_path
      return
    end

    # Record that the user connected using the CBRAIN login page
    cbrain_session[:login_page] = 'CBRAIN'

    # All's good
    redirect_to start_page_path
  end

  # ------------------------------------
  # SessionInfo fake model for API calls
  # ------------------------------------

  def session_info #:nodoc:
    {
      :user_id          => current_user.try(:id),
      :cbrain_api_token => cbrain_session.try(:cbrain_api_token),
    }
  end

  def xml_session_info #:nodoc:
    session_info.to_xml(:root => 'SessionInfo', :dasherize => false)
  end

  def json_session_info #:nodoc:
    session_info
  end

end
