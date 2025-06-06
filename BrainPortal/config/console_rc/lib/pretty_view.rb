
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

# Pretty view for active record objects
$_PV_MAX_SHOW=20
def pv(*args)
  no_log do
    to_show = args.flatten
    to_show.each_with_index do |obj,idx|
      if obj.respond_to?(:pretview)
        puts obj.pretview
      else
        puts "==== Object does not respond to pretview(): #{obj.inspect} ===="
      end
      if idx+1 >= $_PV_MAX_SHOW && to_show.size > $_PV_MAX_SHOW
        puts "Not showing #{to_show.size - $_PV_MAX_SHOW} other entries..."
        break
      end
    end
  end
  true
end

#####################################################
# Add 'pretview' methods to the objects.
# The methods requires access to helpers such
# as pretty_size etc.
#####################################################

# Make sure the classes are loaded
[ Userfile, CbrainTask, User, Group, DataProvider, RemoteResource,
  RemoteResourceInfo, Site, Tool, ToolConfig, Bourreau, DiskQuota, CpuQuota, DataUsage,
  BackgroundActivity ]
# Note that it's important to load PortalTask and/or ClusterTask too, because of its own pre-loading of subclasses.
PortalTask.nil? rescue true
ClusterTask.nil? rescue true

# We need some sort of constant to refer to the console's
# context, which has access to all the pretty helpers etc.
ConsoleCtx ||= self # also in interactive_bourreau_control.rb in the same directory

class Userfile
  def pretview
    report = <<-VIEW
%s #%d "%s"
  Owner:     %d (%s)
  Group:     %d (%s)
  Size:      %s
  NumFiles:  %s
  DP:        %d (%s)
  Created:   %s
  Updated:   %s
  Flags:     %s
  DP Path:   %s
  CachePath: %s
    VIEW
    sprintf report,
      self.class.to_s, self.id, self.browse_name,
      user_id, user.login,
      group_id, group.try(:name),
      (size ? "#{size.to_s} (#{ConsoleCtx.send(:pretty_size,size)})" : "(unk)"),
      (num_files.present? && num_files > 1 ? "(#{num_files} files)" : ""),
      data_provider_id, data_provider.try(:name),
      ConsoleCtx.send(:pretty_past_date,created_at),
      ConsoleCtx.send(:pretty_past_date,updated_at),
      (
       (archived?  ? "Archived"  : "") +
       (hidden?    ? "Hidden"    : "") +
       (immutable? ? "Immutable" : "")
      ),
      self.provider_full_path.to_s,
      self.cache_full_path.to_s
  end
end

class CbrainTask
  def pretview
    report = <<-VIEW
%s #%d (%s)
  Owner:    %d (%s)
  Group:    %d (%s)
  Exec:     %d (%s)
  ToolConf: %d (%s)
  WorkDir:  %s
  WorkSize: %s
  JobID:    %s
  Prereqs:  %s
  ShareWD:  %s
  RunNb:    %d
  ResDP:    %d (%s)
  Created:  %s
  Updated:  %s
  Archived: %s
    VIEW
    sprintf report,
      self.class.to_s, self.id, self.status,
      user_id, user.login,
      group_id, group.try(:name),
      (bourreau_id || 0), (bourreau_id && bourreau_id != 0 && bourreau.try(:name) || "none"),
      (tool_config_id || 0), tool_config.try(:version_name),
      (bourreau_id && bourreau_id != 0 && full_cluster_workdir.presence || "(unk)"),
      (cluster_workdir_size ? "#{cluster_workdir_size.to_s} (#{ConsoleCtx.send(:pretty_size,cluster_workdir_size)})" : "(unk)"),
      (cluster_jobid || "(unk)"),
      (prerequisites.present? ? prerequisites.keys.join(", ") : ""),
      share_wd_tid.to_s,
      run_number,
      (results_data_provider_id || 0), results_data_provider.try(:name) || "",
      ConsoleCtx.send(:pretty_past_date,created_at),
      ConsoleCtx.send(:pretty_past_date,updated_at),
      (archived_status.to_s.capitalize + " " + (workdir_archive_userfile_id || 0).to_s)
  end
end

class User
  def pretview
    report = <<-VIEW
%s #%d "%s"
  Full:     %s
  Email:    %s
  City:     %s
  Country:  %s
  Site:     %d (%s)
  TimeZone: %s
  Created:  %s
  Updated:  %s
  LastConn: %s
  Locked:   %s
    VIEW
    sprintf report,
      self.class.to_s, self.id, self.login,
      full_name,
      email,
      city.presence || "(None)",
      country.presence || "(None)",
      (site_id || 0), site.try(:name) || "No site",
      time_zone,
      ConsoleCtx.send(:pretty_past_date,created_at),
      ConsoleCtx.send(:pretty_past_date,updated_at),
      ConsoleCtx.send(:pretty_past_date,last_connected_at),
      account_locked? ? "Yes" : ""
  end
end

class Group
  def pretview
    report = <<-VIEW
%s #%d "%s"
  Creator:  %d (%s)
  Created:  %s
  Updated:  %s
  Site:     %d (%s)
  Flags:    %s
    VIEW
    sprintf report,
      self.class.to_s, self.id, self.name,
      (self.creator_id || 0), self.creator.try(:login),
      ConsoleCtx.send(:pretty_past_date,created_at),
      ConsoleCtx.send(:pretty_past_date,updated_at),
      (site_id || 0), site.try(:name) || "No site",
      [ (self.invisible? ? "Invisible" : nil),
        (self.public?    ? "Public"    : nil) ].compact.join(", ")
  end
end

class DataProvider
  def pretview
    report = <<-VIEW
%s #%d "%s"
  Owner:    %d (%s)
  Group:    %d (%s)
  TimeZone: %s
  SshPath:  %s
  AltHosts: %s
  Created:  %s
  Updated:  %s
  Flags:    %s %s %s
    VIEW
    sprintf report,
      self.class, self.id, self.name,
      user_id, user.login,
      group_id, group.try(:name),
      time_zone,
      "ssh://#{remote_user.presence || 'none'}@#{remote_host.presence || 'none'}:#{remote_port.presence || 22}#{remote_dir.presence || "/none"}",
      alternate_host, # should be plural
      ConsoleCtx.send(:pretty_past_date,created_at),
      ConsoleCtx.send(:pretty_past_date,updated_at),
      (online?       ? "Online"      : "Offline"),
      (read_only?    ? "ReadOnly"    : "R/W"),
      (not_syncable? ? "NotSyncable" : "Syncable")
  end
end

class RemoteResource
  def pretview
    report = <<-VIEW
%s #%d "%s"
  Owner:    %d (%s)
  Group:    %d (%s)
  SshPath:  ssh://%s@%s:%s%s
  ProxHost: %s
  TimeZone: %s
  SiteURL:  %s
  HelpURL:  %s
  HelpMail: %s
  FromMail: %s
  StatPage: %s
  Cache:    %s
  DPIgnPat: %s
  CacheMD5: %s
  CMS:      %s
  Queue:    %s
  QsubExt:  %s
  GridPath: %s
  Workers:  %d x %d secs, log=%s, verbose=%s
  Created:  %s
  Updated:  %s
  Docker:   %s
  Singularity: %s
  Flags:    %s %s %s
    VIEW
    sprintf report,
      self.class.to_s, self.id, self.name,
      user_id, user.login,
      group_id, group.try(:name),
      ssh_control_user.presence || "none",
      ssh_control_host.presence || "none",
      ssh_control_port.presence || 22,
      ssh_control_rails_dir.presence || "/none",
      proxied_host.presence || "",
      time_zone.presence || "none",
      site_url_prefix.presence || "",
      help_url.presence || "",
      support_email.presence || "",
      system_from_email.presence || "",
      external_status_page_url.presence || "",
      dp_cache_dir.presence || "(NONE!)",
      dp_ignore_patterns.presence || "",
      cache_md5 || "(NONE!)",
      cms_class.presence || "",
      cms_default_queue.presence || "",
      cms_extra_qsub_args.presence || "",
      cms_shared_dir.presence || "",
      workers_instances.presence || 0,
      workers_chk_time.presence || 0,
      workers_log_to.presence || "",
      workers_verbose.presence || "",
      ConsoleCtx.send(:pretty_past_date,created_at),
      ConsoleCtx.send(:pretty_past_date,updated_at),
      docker_executable_name.presence || "",
      singularity_executable_name.presence || "",
      (online? ? "Online" : "Offline"),
      (read_only? ? "ReadOnly" : "R/W"),
      (portal_locked? ? "LOCKED" : "")
  end
end

class Site
  def pretview
    report = <<-VIEW
Site #%d "%s"
  Created:  %s
  Updated:  %s
  Desc:     %s
    VIEW
    sprintf report,
      self.id, self.name,
      ConsoleCtx.send(:pretty_past_date,created_at),
      ConsoleCtx.send(:pretty_past_date,updated_at),
      description.presence || "(None)"
  end
end

class Tool
  def pretview
    report = <<-VIEW
Tool #%d "%s"
  Owner:    %d (%s)
  Group:    %d (%s)
  Categ:    %s
  Class:    %s
  SelText:  %s
  URL:      %s
  PakName:  %s
  AppType:  %s
  AppTags:  %s
  Created:  %s
  Updated:  %s
  Desc:     %s
    VIEW
    sprintf report,
      self.id, self.name,
      user_id, user.login,
      group_id, group.try(:name),
      category.presence || "",
      cbrain_task_class_name.presence || "",
      select_menu_text.presence || "",
      url.presence || "",
      application_package_name.presence || "",
      application_type.presence || "",
      application_tags.presence || "",
      ConsoleCtx.send(:pretty_past_date,created_at),
      ConsoleCtx.send(:pretty_past_date,updated_at),
      description.presence || "(None)"
  end
end

class ToolConfig
  def pretview
    report = <<-VIEW
ToolConfig #%d "%s"
  Group:           %d (%s)
  Tool:            %d (%s)
  Exec:            %d (%s)
  nCPUs:           %d
  ContainerEngine: %s
  ContainerImage:  %s%s
  ContainerID:     %d (%s)
  QsubExt:         "%s"
    VIEW
    sprintf report,
      self.id, self.version_name.presence || "",
      group_id, group.try(:name),
      tool_id.presence || 0, tool.try(:name),
      bourreau_id.presence || 0, bourreau.try(:name),
      ncpus.presence || 0,
      container_engine.presence || "(none)",
      container_index_location || "",
      containerhub_image_name.presence || "",
      container_image_userfile_id.presence || 0,
      container_image.try(:name) || "none",
      extra_qsub_args.presence || ""
  end
end

class DiskQuota
  def pretview
    report = <<-VIEW
DiskQuota #%d
  Owner:    %d (%s)
  DP:       %d (%s)
  MaxBytes: %d (%s)
  MaxFiles: %d
  Created:  %s
  Updated:  %s
    VIEW
    sprintf report,
      self.id,
      user_id, (user_id == 0 ? "Default for all users" : user.login),
      data_provider_id, data_provider.try(:name),
      self.max_bytes, ConsoleCtx.send(:pretty_size, self.max_bytes),
      self.max_files,
      ConsoleCtx.send(:pretty_past_date,created_at),
      ConsoleCtx.send(:pretty_past_date,updated_at)
  end
end

class CpuQuota
  def pretview
    report = <<-VIEW
CpuQuota #%d
  Owner:    %d (%s)
  Group:    %d (%s)
  Exec:     %d (%s)
  MaxWeek:  %s
  MaxMonth: %s
  MaxEver:  %s
  Created:  %s
  Updated:  %s
    VIEW
    sprintf report,
      self.id,
      user_id, (user_id == 0 ? "All users of group" : user.login),
      group_id, (group_id == 0 ? "Specified user" : Group.where(:id => group_id).first.try(:name)),
      remote_resource_id, (remote_resource_id == 0 ? "Any exec" : RemoteResource.where(:id => remote_resource_id).first.try(:name)),
      ConsoleCtx.send(:pretty_elapsed, self.max_cpu_past_week || 0, :num_components => 2),
      ConsoleCtx.send(:pretty_elapsed, self.max_cpu_past_month || 0, :num_components => 2),
      ConsoleCtx.send(:pretty_elapsed, self.max_cpu_ever || 0, :num_components => 2),
      ConsoleCtx.send(:pretty_past_date,created_at),
      ConsoleCtx.send(:pretty_past_date,updated_at)
  end
end

class DataUsage
  def pretview
    report = <<-VIEW
DataUsage #%d
  User:    %d (%s)
  Group:   %d (%s)
  Month:   %s
  Views     (Count)   : %d
            (NumFiles): %d
  Downloads (Count)   : %d
            (NumFiles): %d
  Copies    (Count)   : %d
            (NumFiles): %d
  TaskSetup (Count)   : %d
            (NumFiles): %d
    VIEW
    sprintf report,
      self.id,
      user_id,  user.login,
      group_id, group.name,
      self.yearmonth,
      views_count,       views_numfiles,
      downloads_count,   downloads_numfiles,
      copies_count,      copies_numfiles,
      task_setups_count, task_setups_numfiles
  end
end

class BackgroundActivity
  def pretview
    report = <<-VIEW
%s #%d (%s)
  Owner:    %d (%s)
  Resource: %d (%s)
  NumItems: %d
  NumOK:    %d
  NumBAD:   %d
  Updated:  %s
  StartAt:  %s
  Repeat:   %s
    VIEW
    sprintf report,
      self.class.to_s.demodulize, self.id, self.status,
      self.user_id, self.user.login,
      self.remote_resource_id, self.remote_resource.name,
      self.items.size,
      self.num_successes, self.num_failures,
      ConsoleCtx.send(:pretty_past_date,updated_at),
      self.start_at.presence || '(None)',
      self.repeat
  end
end


(CbrainConsoleFeatures ||= []) << <<FEATURES
========================================================
Feature: Pretty View for some objects
========================================================
  pv obj [, obj , ...]

  If an object responds to 'pretview', show that view.
  Currently implemented: User, CbrainTask, Group, and
  about a dozen other common CBRAIN models.
FEATURES

