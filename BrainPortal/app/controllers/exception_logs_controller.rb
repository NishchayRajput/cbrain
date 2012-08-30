
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

# Controller for viewing or managing exception logs.
class ExceptionLogsController < ApplicationController
  
  Revision_info=CbrainFileRevision[__FILE__] #:nodoc:

  before_filter :login_required 
  before_filter :admin_role_required

  def index #:nodoc:
    @filter_params["sort_hash"]["order"] ||= 'exception_logs.created_at'
    @filter_params["sort_hash"]["dir"]   ||= 'DESC'
    
    @filtered_scope = base_filtered_scope
    @exception_logs = base_sorted_scope(@filtered_scope).paginate(:page => @current_page, :per_page => @per_page)

    current_session.save_preferences_for_user(current_user, :exception_logs, :per_page)

    respond_to do |format|
      format.html # index.html.erb
      format.js
      format.xml  { render :xml => @exception_logs }
    end
  end

  def show #:nodoc:
    @exception_log = ExceptionLog.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @exception_log }
    end
  end

  def destroy #:nodoc:
    @exception_logs = ExceptionLog.find(params[:exception_log_ids])
    @exception_logs.each(&:destroy)
    
    flash[:notice] = "#{view_pluralize(@exception_logs.count, "exception")} deleted."

    respond_to do |format|
      format.html { redirect_to(:action => :index) }
      format.js   { redirect_to(:action => :index) }
      format.xml  { head :ok }
    end
  end
end
