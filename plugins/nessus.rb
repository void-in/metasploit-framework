# $Id$ $Revision$
require 'nessus/nessus-xmlrpc'
require 'rex/parser/nessus_xml'

module Msf

  class Plugin::Nessus < Msf::Plugin
      
    class ConsoleCommandDispatcher
      include Msf::Ui::Console::CommandDispatcher
      
      def name
        "Nessus"
      end

      def xindex
        "#{Msf::Config.get_config_root}/nessus_index"
      end

      def nessus_yaml
        "#{Msf::Config.get_config_root}/nessus.yaml"
      end
         
      def commands
        {
          "nessus_connect" => "Connect to a nessus server: nconnect username:password@hostname:port <verify_ssl>.",
          "nessus_admin" => "Checks if user is an admin.",
          "nessus_help" => "Get help on all commands.",
          "nessus_logout" => "Terminate the session.",
          "nessus_server_status" => "Check the status of your Nessus server.",
          "nessus_server_properties" => "Nessus server properties such as feed type, version, plugin set and server UUID.",
          "nessus_report_list" => "List all Nessus reports.",
          "nessus_report_get" => "Import a report from the nessus server in Nessus v2 format.",
          "nessus_report_del" => "Delete a report.",
          "nessus_report_vulns" => "Get list of vulns from a report.",
          "nessus_report_hosts" => "Get list of hosts from a report.",
          "nessus_report_host_ports" => "Get list of open ports from a host from a report.",
          "nessus_report_host_detail" => "Detail from a report item on a host.",
          "nessus_scan_list" => "List all currently running Nessus scans.",
          "nessus_scan_new" => "Create new Nessus Scan.",
          "nessus_scan_pause" => "Pause a Nessus Scan.",
          "nessus_scan_pause_all" => "Pause all Nessus Scans.",
          "nessus_scan_stop" => "Stop a Nessus Scan.",
          "nessus_scan_stop_all" => "Stop all Nessus Scans.",
          "nessus_scan_resume" => "Resume a Nessus Scan.",
          "nessus_scan_resume_all" => "Resume all Nessus Scans.",
          "nessus_scan_details" => "Return detailed information of a given scan.",
          "nessus_scan_export" => "Export a scan result in either Nessus, HTML, PDF, CSV, or DB format.",
          "nessus_scan_export_status" => "Check the status of scan export",
          "nessus_user_list" => "Show Nessus Users.",
          "nessus_user_add" => "Add a new Nessus User.",
          "nessus_user_del" => "Delete a Nessus User.",
          "nessus_user_passwd" => "Change Nessus Users Password.",
          "nessus_family_list" => "List all the plugin families along with their corresponding family IDs and plugin count.",
          "nessus_plugin_details" => "List details of a particular plugin.",
          "nessus_plugin_list" => "Display plugin details in a particular plugin family.",
          "nessus_policy_list" => "List all polciies.",
          "nessus_policy_del" => "Delete a policy.",
          "nessus_index" => "Manually generates a search index for exploits.",
          "nessus_template_list" => "List all the templates on the server.",
          "nessus_db_scan" => "Create a scan of all ips in db_hosts.",
          "nessus_save" => "Save username/passowrd/server/port details.",
          "nessus_folder_list" => "List folders configured on the Nessus server",
          "nessus_scanner_list" => "List the configured scanners on the Nessus server",
          "nessus_scan_launch" => "Launch a previously added scan",
          "nessus_family_list" => "List all the families of plugins"
        }  
      end

      #creates the index of exploit details to make searching for exploits much faster.
      def create_xindex
        start = Time.now
        print_status("Creating Exploit Search Index - (#{xindex}) - this won't take long.")
        count = 0
        #Use Msf::Config.get_config_root as the location.
        File.open("#{xindex}", "w+") do |f|
          #need to add version line.
          f.puts(Msf::Framework::RepoRevision)
          framework.exploits.sort.each { |refname, mod|
          stuff = ""
          o = nil
          begin
            o = mod.new
            rescue ::Exception
          end
          stuff << "#{refname}|#{o.name}|#{o.platform_to_s}|#{o.arch_to_s}"
          next if not o
            o.references.map do |x|
              if !(x.ctx_id == "URL")
                if (x.ctx_id == "MSB")
                  stuff << "|#{x.ctx_val}"
                else
                  stuff << "|#{x.ctx_id}-#{x.ctx_val}"
                end
              end
            end
            stuff << "\n"
            f.puts(stuff)
          }
        end
        total = Time.now - start
        print_status("It has taken : #{total} seconds to build the exploits search index")
      end
      
      def nessus_index
        if File.exist?("#{xindex}")
          #check if it's version line matches current version.
          File.open("#{xindex}") {|f|
            line = f.readline
            line.chomp!
            if line.to_i == Msf::Framework::RepoRevision
              print_good("Exploit Index - (#{xindex}) - is valid.")
            else
              create_xindex
            end
          }
        else
          create_xindex
        end
      end
         
      def cmd_nessus_folder_list
        if !nessus_verify_token
          return
        end
        list = @n.list_folders
        tbl = Rex::Ui::Text::Table.new(
          'Columns' => [
            "ID",
            "Name",
            "Type"
          ])
        list["folders"].each { |folder|
        tbl << [ folder["id"], folder["name"], folder["type"] ]
        }
        print_line tbl.to_s
      end
         
      def cmd_nessus_scanner_list
        if !nessus_verify_token
          return
        end
        if !@n.is_admin
          return
        end
        list = @n.list_scanners
        tbl = Rex::Ui::Text::Table.new(
          'Columns' => [
            "ID",
            "Name",
            "Status",
            "Platform",
            "Plugin Set",
            "UUID"
          ])
        list.each { |scanner|
        tbl << [ scanner["id"], scanner["name"], scanner["status"], scanner["platform"], scanner["loaded_plugin_set"], scanner["uuid"] ]
        }
        print_line tbl.to_s
      end

      def cmd_nessus_index
        nessus_index
      end
         
      def cmd_nessus_save(*args)
        #if we are logged in, save session details to nessus.yaml
        if args[0] == "-h"
          print_status(" nessus_save")
          return
        end
        if args[0]
          print_status("Usage: ")
          print_status("nessus_save")
          return
        end
        group = "default"
        if ((@user and @user.length > 0) and (@host and @host.length > 0) and (@port and @port.length > 0 and @port.to_i > 0) and (@pass and @pass.length > 0))
          config = Hash.new
          config = {"#{group}" => {'username' => @user, 'password' => @pass, 'server' => @host, 'port' => @port}}
          File.open("#{nessus_yaml}", "w+") do |f|
            f.puts YAML.dump(config)
          end
          print_good("#{nessus_yaml} created.")
        else
          print_error("Missing username/password/server/port - relogin and then try again.")
          return
        end
      end
         
      def cmd_nessus_db_scan(*args)
        if args[0] == "-h"
          print_status("nessus_db_scan <policy id> <scan name>")
          print_status("Example:> nessus_db_scan 1 \"My Scan\"")
          print_status()
          print_status("Creates a scan based on all the hosts listed in db_hosts.")
          print_status("use nessus_policy_list to list all available policies")
          return
        end
        if !nessus_verify_token
          return
        end
        case args.length
        when 2
          pid = args[0].to_i
          name = args[1]
        else
          print_status("Usage: ")
          print_status("nessus_db_scan <policy id> <scan name>")
          print_status("use nessus_policy_list to list all available policies")
          return
        end
        if check_policy(pid)
          print_error("That policy does not exist.")
          return
        end
        tgts = ""
        framework.db.hosts(framework.db.workspace).each do |host|
          tgts << host.address
          tgts << ","
        end
        tgts.chop!
        print_status("Creating scan from policy number #{pid}, called \"#{name}\" and scanning all hosts in workspace")
        scan = @n.scan_new(pid, name, tgts)
        if scan
          print_status("Scan started.  uid is #{scan}")
        end
      end
         
      def cmd_nessus_logout
        logout = @n.user_logout
        status = logout.to_s
        if status == "200"
          print_good("User account logged out successfully")
          @token = ""
        elsif status == "403"
          print_status("No user session to logout")
        else
          print_error("There was some problem in logging out the user #{@user}")
        end
        return
      end
         
      def cmd_nessus_help(*args)
        tbl = Rex::Ui::Text::Table.new(
          'Columns' => [
            "Command",
            "Help Text"
            ],
          'SortIndex' => -1
          )
        tbl << [ "Generic Commands", "" ]
        tbl << [ "-----------------", "-----------------"]
        tbl << [ "nessus_connect", "Connect to a nessus server" ]
        tbl << [ "nessus_logout", "Logout from the nessus server" ]
        tbl << [ "nessus_help", "Listing of available nessus commands" ]
        tbl << [ "nessus_server_status", "Check the status of your Nessus Server" ]
        tbl << [ "nessus_admin", "Checks if user is an admin" ]
        tbl << [ "nessus_server_feed", "Nessus Feed Type" ]
        tbl << [ "", ""]
        tbl << [ "Reports Commands", "" ]
        tbl << [ "-----------------", "-----------------"]   
        tbl << [ "nessus_scan_export", "Export a scan into either Nessus, HTML, PDF, CSV, or DB format." ]
        tbl << [ "nessus_scan_export_status", "Check the status of scan export" ]
        tbl << [ "", ""]
        tbl << [ "Scan Commands", "" ]
        tbl << [ "-----------------", "-----------------"]
        tbl << [ "nessus_scan_new", "Create new Nessus Scan" ]
        tbl << [ "nessus_scan_pause", "Pause a Nessus Scan" ]
        tbl << [ "nessus_scan_pause_all", "Pause all Nessus Scans" ]
        tbl << [ "nessus_scan_stop", "Stop a Nessus Scan" ]
        tbl << [ "nessus_scan_stop_all", "Stop all Nessus Scans" ]
        tbl << [ "nessus_scan_resume", "Resume a Nessus Scan" ]
        tbl << [ "nessus_scan_resume_all", "Resume all Nessus Scans" ]
        tbl << [ "", ""]
        tbl << [ "Plugin Commands", "" ]
        tbl << [ "-----------------", "-----------------"]
        tbl << [ "nessus_plugin_list", "Display plugin details in a particular plugin family." ]
        tbl << [ "nessus_plugin_family_list", "List all the plugin families along with their corresponding family IDs and plugin count." ]
        tbl << [ "nessus_plugin_details", "List details of a particular plugin" ]
        tbl << [ "", ""]
        tbl << [ "User Commands", "" ]
        tbl << [ "-----------------", "-----------------"]
        tbl << [ "nessus_user_list", "Show Nessus Users" ]
        tbl << [ "nessus_user_add", "Add a new Nessus User" ]
        tbl << [ "nessus_user_del", "Delete a Nessus User" ]
        tbl << [ "nessus_user_passwd", "Change Nessus Users Password" ]
        tbl << [ "", ""]
        tbl << [ "Policy Commands", "" ]
        tbl << [ "-----------------", "-----------------"]
        tbl << [ "nessus_policy_list", "List all polciies" ]
        tbl << [ "nessus_policy_del", "Delete a policy" ]
        print_status ""
        print_line tbl.to_s
        print_status ""
      end
         
      def cmd_nessus_server_properties(*args)
        if args[0] == "-h"
          print_status("nessus_server_feed")
          print_status("Example:> nessus_server_feed")
          print_status()
          print_status("Returns information about the feed type and server version.")
          return
        end
        resp = @n.server_properties
        tbl = Rex::Ui::Text::Table.new(
          'Columns' => [
            'Feed',
            'Type',
            'Nessus Version',
            'Nessus Web Version',
            'Plugin Set',
            'Server UUID'
          ])
        tbl << [ resp["feed"], resp["nessus_type"], resp["server_version"], resp["nessus_ui_version"], resp["loaded_plugin_set"], resp["server_uuid"] ]
        print_line tbl.to_s
      end
         
      def nessus_verify_token
        if @token.nil? or @token == ''
          ncusage
          return false
        end
        true
      end
         
      def nessus_verify_db
        if !(framework.db and framework.db.active)
          print_error("No database has been configured, please use db_create/db_connect first")
          return false
        end
        true
      end
         
      def ncusage
        print_status("%redYou must do this before any other commands.%clr")
        print_status("Usage: ")
        print_status("nessus_connect username:password@hostname:port <ssl_verify>")
        print_status("Example:> nessus_connect msf:msf@192.168.1.10:8834")
        print_status(" OR")
        print_status("nessus_connect username@hostname:port ssl_verify")
        print_status("Example:> nessus_connect msf@192.168.1.10:8834 ssl_verify")
        print_status("OR")
        print_status("nessus_connect hostname:port ssl_verify")
        print_status("Example:> nessus_connect 192.168.1.10:8834 ssl_verify")
        print_status("OR")
        print_status("nessus_connect")
        print_status("Example:> nessus_connect")
        print_status("This only works after you have saved creds with nessus_save")
        return
      end
         
      def cmd_nessus_connect(*args)
        # Check if config file exists and load it
        if ! args[0]
          if File.exist?(nessus_yaml)
            lconfig = YAML.load_file(nessus_yaml)
            @user = lconfig['default']['username']
            @pass = lconfig['default']['password']
            @host = lconfig['default']['server']
            @port = lconfig['default']['port']
            nessus_login
            return
          else
            ncusage
            return
          end
        end
        if args[0] == "-h"
          print_status("%redYou must do this before any other commands.%clr")
          print_status("Usage: ")
          print_status("nessus_connect username:password@hostname:port <ssl_verify/ssl_ignore>")
          print_status("%bldusername%clr and %bldpassword%clr are the ones you use to login to the nessus web front end")
          print_status("%bldhostname%clr can be an IP address or a DNS name of the Nessus server.")
          print_status("%bldport%clr is the RPC port that the Nessus web front end runs on. By default it is TCP port 8834.")
          print_status("The \"ssl_verify\" to verify the SSL certificate used by the Nessus front end. By default the server")
          print_status("use a self signed certificate, therefore, users should use ssl_ignore.")
          return
        end
        if !@token == ''
          print_error("You are already authenticated.  Call nessus_logout before authing again")
          return
        end
        if(args.length == 0 or args[0].empty?)
          ncusage
          return
        end
        @user = @pass = @host = @port = @sslv = nil
        case args.length
        when 1,2
          if args[0].include? "@"
            cred,targ = args[0].split('@', 2)
            @user,@pass = cred.split(':', 2)
            targ ||= '127.0.0.1:8834'
            @host,@port = targ.split(':', 2)
            @port ||= '8834'
            @sslv = args[1]
          else
            @host,@port = args[0].split(':', 2)
            @port ||= '8834'
            @sslv = args[1]
          end
        when 3,4,5
          ncusage
          return
        else
          ncusage
          return
        end
        if /\/\//.match(@host)
          ncusage
          return
        end
        if !@user
          print_error("Missing Username")
          ncusage
          return
        end
        if !@pass
          print_error("Missing Password")
          ncusage
          return
        end
        if !((@user and @user.length > 0) and (@host and @host.length > 0) and (@port and @port.length > 0 and @port.to_i > 0) and (@pass and @pass.length > 0))
          ncusage
          return
        end
        nessus_login
      end
         
      def nessus_login
        if !((@user and @user.length > 0) and (@host and @host.length > 0) and (@port and @port.length > 0 and @port.to_i > 0) and (@pass and @pass.length > 0))
          print_status("You need to connect to a server first.")
          ncusage
          return
        end
        @url = "https://#{@host}:#{@port}/"
        print_status("Connecting to #{@url} as #{@user}")
        @n = Nessus::Client.new(@url, @user, @pass,@sslv)
        if @n.authenticated
          print_status("User #{@user} authenticated successfully.")
          @token = 1
        else
          print_error("Error connecting/logging to the server!")
          return
        end
      end
         
      def cmd_nessus_report_list(*args)
        if args[0] == "-h"
          print_status("nessus_report_list")
          print_status("Example:> nessus_report_list")
          print_status("Generates a list of all reports visable to your user.")
          return
        end
        if !nessus_verify_token
          return
        end
        list=@n.report_list_hash
        tbl = Rex::Ui::Text::Table.new(
          'Columns' => [
            'ID',
            'Name',
            'Status',
            'Date'
          ])
        list.each {|report|
        t = Time.at(report['timestamp'].to_i)
        tbl << [ report['id'], report['name'], report['status'], t.strftime("%H:%M %b %d %Y") ]
        }
        print_good("Nessus Report List")
        print_good "\n"
        print_line tbl.to_s + "\n"
        print_status("You can:")
        print_status(" Get a list of hosts from the report: nessus_report_hosts <report id>")
      end
         
      def check_scan(*args)
        case args.length
        when 1
          rid = args[0]
        else
          print_error("No Report ID Supplied")
          return
        end
        scans = @n.scan_list_hash
        scans.each {|scan|
        if scan['id'] == rid
          return true
        end
        }
        return false
      end
         
      def cmd_nessus_report_get(*args)
        if args[0] == "-h"
          print_status("nessus_report_get <report id>")
          print_status("Example:> nessus_report_get f0eabba3-4065-7d54-5763-f191e98eb0f7f9f33db7e75a06ca")
          print_status()
          print_status("This command pulls the provided report from the nessus server in the nessusv2 format")
          print_status("and parses it the same way db_import_nessus does.  After it is parsed it will be")
          print_status("available to commands such as db_hosts, db_vulns, db_services and db_autopwn.")
          print_status("Use: nessus_report_list to obtain a list of report id's")
          return
        end
        if !nessus_verify_token
          return
        end
        if !nessus_verify_db
          return
        end
        if(args.length == 0 or args[0].empty? or args[0] == "-h")
          print_status("Usage: ")
          print_status("nessus_report_get <report id> ")
          print_status("use nessus_report_list to list all available reports for importing")
          return
        end
        rid = nil
        case args.length
        when 1
          rid = args[0]
        else
          print_status("Usage: ")
          print_status("nessus_report_get <report id> ")
          print_status("use nessus_report_list to list all available reports for importing")
          return
        end
        if check_scan(rid)
          print_error("That scan is still running.")
          return
        end
        content = nil
        content=@n.report_file_download(rid)
        if content.nil?
          print_error("Failed, please reauthenticate")
          return
        end
        print_status("importing " + rid)
        framework.db.import({:data => content}) do |type,data|
          case type
          when :address
            print_line("%bld%blu[*]%clr %bld#{data}%clr")
          end
        end
        print_good("Done")
      end
         
      def cmd_nessus_scan_list(*args)
        if args[0] == "-h"
          print_status("nessus_scan_status")
          print_status("Example:> nessus_scan_status")
          print_status()
          print_status("Returns a list of information about currently running scans.")
          return
        end
        if !nessus_verify_token
          return
        end
        list=@n.scan_list
        if list.to_s.empty?
          print_status("No scans performed.")
          return
        else
        tbl = Rex::Ui::Text::Table.new(
          'Columns' => [
            'Scan ID',
            'Name',
            'Owner',
            'Started',
            'Status',
            'Folder'
          ])
           
        list["scans"].each {|scan|
        if args[0] == "-r"
          if scan["status"] == "running"
            tbl << [ scan["id"], scan["name"], scan["owner"], scan["starttime"], scan["status"], scan["folder_id"] ]
          end
          elsif args[0] == "-p"
            if scan["status"] == "paused"
              tbl << [ scan["id"], scan["name"], scan["owner"], scan["starttime"], scan["status"], scan["folder_id"] ]
            end
          elsif args[0] == "-c"
            if scan["status"] == "canceled"
              tbl << [ scan["id"], scan["name"], scan["owner"], scan["starttime"], scan["status"], scan["folder_id"] ]
            end
          else
            tbl << [ scan["id"], scan["name"], scan["owner"], scan["starttime"], scan["status"], scan["folder_id"] ]
          end
          }
          print_line tbl.to_s
        end
      end
         
      def cmd_nessus_template_list(*args)
        if args[0] == "-h"
          print_status("nessus_template_list")
          print_status("Example:> nessus_template_list")
          print_status()
          print_status("Returns a list of information about the server templates..")
          return
        end
        if !nessus_verify_token
          return
        end
        list=@n.template_list_hash
        if list.empty?
          print_status("No Templates Created.")
          print_status("You can:")
          print_status("List of completed scans: nessus_report_list")
          print_status("Create a template: nessus_template_new <policy id> <scan name> <target(s)>")
          return
        end
        tbl = Rex::Ui::Text::Table.new(
          'Columns' => [
            'Template ID',
            'Policy ID',
            'Name',
            'Owner',
            'Target'
          ])
        list.each {|template|
        tbl << [ template['name'], template['pid'], template['rname'], template['owner'], template['target'] ]
        }
        print_good("Templates")
        print_good "\n"
        print_line tbl.to_s + "\n"
        print_good "\n"
        print_status("You can:")
        print_good("Import Nessus report to database: nessus_report_get <reportid>")
      end
         
      def cmd_nessus_user_list(*args)
        if args[0] == "-h"
          print_status("nessus_user_list")
          print_status("Example:> nessus_user_list")
          print_status()
          print_status("Returns a list of the users on the Nessus server and their access level.")
          return
        end
        if !nessus_verify_token
          return
        end
        if !@n.is_admin
          print_status("Your Nessus user is not an admin")
        end
        list=@n.list_users
        tbl = Rex::Ui::Text::Table.new(
          'Columns' => [
            'ID',
            'Name',
            'Username',
            'Type',
            'Email',
            'Permissions'
          ])
        list["users"].each { |user|
        tbl << [ user["id"], user["name"], user["username"], user["type"], user["email"], user["permissions"] ]
        }
        print_line tbl.to_s
      end
         
      def cmd_nessus_server_status(*args)
        if args[0] == "-h"
          print_status("nessus_server_status")
          print_status("Example:> nessus_server_status")
          print_status()
          print_status("Returns some status items for the server..")
          return
        end
        tbl = Rex::Ui::Text::Table.new(
          'Columns' => [
            'Status',
            'Progress'
          ])
        list = @n.server_status
        tbl << [ list["progress"], list["status"] ]
        print_line tbl.to_s
      end
         
      def cmd_nessus_family_list(*args)
        if args[0] == "-h"
          print_status("nessus_family_list")
          print_status("Example:> nessus_family_list")
          print_status()
          print_status("Returns a list of all the plugin families along with their corresponding family IDs and plugin count.")
          return
        end
        list = @n.list_families
        tbl = Rex::Ui::Text::Table.new(
          'Columns' => [
            'Family ID',
            'Family Name',
            'Number of Plugins'
          ])
        list.each { |family|
        tbl << [ family["id"], family["name"], family["count"] ]
        }
        print_line tbl.to_s
      end
         
      def check_policy(*args)
        case args.length
        when 1
          pid = args[0]
        else
          print_error("No Policy ID supplied.")
          return
        end
        pol = @n.list_policies
        pol["policies"].each {|p|
        if p["template_uuid"] == pid
          return true
        end
        }
        return false
      end
         
      def cmd_nessus_scan_new(*args)
        if args[0] == "-h"
          print_status("nessus_scan_new <UUID of Policy> <Scan name> <Description> <Targets>")
          print_status("Use nessus_policy_list to list all available policies with their corresponding UUIDs")
          return
        end
        if !nessus_verify_token
          return
        end
        case args.length
        when 4
          uuid = args[0]
          scan_name = args[1]
          description = args[2]
          targets = args[3]
        else
          print_status("Usage: ")
          print_status("nessus_scan_new <UUID of Policy> <Scan name> <Description> <Targets>>")
          print_status("Use nessus_policy_list to list all available policies with their corresponding UUIDs")
          return
        end
        if check_policy(uuid)
          print_status("Creating scan from policy number #{uuid}, called \"#{scan_name} - #{description}\" and scanning #{targets}")
          scan = @n.scan_create(uuid, scan_name, description, targets)
          tbl = Rex::Ui::Text::Table.new(
            'Columns' => [
              "Scan ID",
              "Scanner ID",
              "Policy ID",
              "Targets",
              "Owner"
            ])
          print_status("New scan added")
          tbl << [ scan["scan"]["id"], scan["scan"]["scanner_id"], scan["scan"]["policy_id"], scan["scan"]["custom_targets"], scan["scan"]["owner"] ]
          print_line tbl.to_s
        else
          print_error("The policy does not exist")
        end
      end

      def cmd_nessus_scan_details(*args)
        if args[0] == "-h"
          print_status("nessus_scan_details <scan ID> <category>")
          print_status("Availble categories are info, hosts, vulnerabilities, and history")
          print_status("Use nessus_scan_list to list all available scans with their corresponding scan IDs")
          return
        end
        if !nessus_verify_token
           return
        end
        case args.length
        when 2
          scan_id = args[0]
          category = args[1]
          if category.in?(['info', 'hosts', 'vulnerabilities', 'history'])
            category = args[1]
          else
            print_error("Invalid category. The available categories are info, hosts, vulnerabilities, and history")
            return
          end
        else
          print_status("Usage: ")
          print_status("nessus_scan_details <scan ID> <category>")
          print_status("Availble categories are info, hosts, vulnerabilities, and history")
          print_status("Use nessus_scan_list to list all available scans with their corresponding scan IDs")
          return
        end
        details = @n.scan_details(scan_id)
        if category == "info"
          tbl = Rex::Ui::Text::Table.new(
            'Columns' => [
              "Status",
              "Policy",
              "Scan Name",
              "Scan Targets",
              "Scan Start Time",
              "Scan End Time"
            ])
         tbl << [ details["info"]["status"], details["info"]["policy"], details["info"]["name"], details["info"]["targets"], details["info"]["scan_start"], details["info"]["scan_end"] ]
        elsif category == "hosts"
          tbl = Rex::Ui::Text::Table.new(
            'Columns' => [
              "Host ID",
              "Hostname",
              "% of Critical Findings",
              "% of High Findings",
              "% of Medium Findings",
              "% of Low Findings"
            ])
          details["hosts"].each { |host|
          tbl << [ host["host_id"], host["hostname"], host["critical"], host["high"], host["medium"], host["low"] ]
          }
        elsif category == "vulnerabilities"
          tbl = Rex::Ui::Text::Table.new(
            'Columns' => [
              "Plugin ID",
              "Plugin Name",
              "Plugin Family",
              "Count"
            ])
          details["vulnerabilities"].each { |vuln|
          tbl << [ vuln["plugin_id"], vuln["plugin_family"], vuln["plugin_family"], vuln["count"] ]
          }
        elsif category == "history"
          tbl = Rex::Ui::Text::Table.new(
            'Columns' => [
              "History ID",
              "Status",
              "Creation Date",
              "Last Modification Date"
            ])
          details["history"].each { |hist|
          tbl << [ hist["history_id"], hist["status"], hist["creation_date"], hist["modification_date"] ]
          }
        end
        print_line tbl.to_s
      end

      def cmd_nessus_scan_export(*args)
        if args[0] == "-h"
          print_status("nessus_scan_export <scan ID> <export format>")
          print_status("The available export formats are Nessus, HTML, PDF, CSV, or DB")
          print_status("Use nessus_scan_list to list all available scans with their corresponding scan IDs")
          return
        end
        if !nessus_verify_token
          return
        end
        case args.length
        when 2
          scan_id = args[0]
          format = args[1]
        else
          print_status("Usage: ")
          print_status("nessus_scan_export <scan ID> <export format>")
          print_status("The available export formats are Nessus, HTML, PDF, CSV, or DB")
          print_status("Use nessus_scan_list to list all available scans with their corresponding scan IDs")
          return
        end
        if format.in?(['nessus','html','pdf','csv','db'])
          export = @n.scan_export(scan_id, format)
          if export["file"]
            file_id = export["file"]
            print_good("The export file ID for scan ID #{scan_id} is #{file_id}")
            print_status("Use nessus_scan_export_status <file ID> to get the export status. Once the status is ready, use nessus_scan_report_download <file ID> to download the report.")
          else
            print_error(export)
          end
        else
          print_error("Invalid export format. The available export formats are Nessus, HTML, PDF, CSV, or DB")
          return
        end
      end

      def nessus_scan_report_download(*args)
        if args[0] == "-h"
          print_status("nessus_scan_report_download <scan_id> <file ID> ")
          print_status("Use nessus_scan_export_status <scan ID> <file ID> to check the export status.")
          return
        end
        if !nessus_verify_token
          return
        end
        case args.length
        when 2
          scan_id = args[0]
          file_id = args[1]
          report = @n.scan_report_download
        end

      end

      def cmd_nessus_scan_export_status(*args)
        if args[0] == "-h"
          print_status("nessus_scan_export_status <scan ID> <file ID>")
          print_status("Use nessus_scan_export <scan ID> <format> to export a scan and get its file ID")
        end
        if !nessus_verify_token
          return
        end
        case args.length
        when 2
          scan_id = args[0]
          file_id = args[1]
          status = @n.scan_export_status(scan_id, file_id)
          if status == "ready"
            print_status("The status of scan ID #{scan_id} export is ready.")
          else
            print_error("There was some problem in exporting the scan. The error message is #{status}")
          end
        else
          print_status("Usage: ")
          print_status("nessus_scan_export_status <scan ID> <file ID>")
          print_status("Use nessus_scan_export <scan ID> <format> to export a scan and get its file ID")
        end
      end
         
      def cmd_nessus_scan_launch(*args)
        if args[0] == "-h"
          print_status("nessus_scan_launch <scan ID>")
          print_status("Use nessus_scan_list to list all the availabla scans with their corresponding scan IDs")
        end
        if !nessus_verify_token
          return
        end
        case args.length
        when 1
          scan_id = args[0]
        else
          print_status("Usage: ")
          print_status("nessus_scan_launch <scan ID>")
          print_status("Use nessus_scan_list to list all the availabla scans with their corresponding scan IDs")
          return
        end
        launch = @n.scan_launch(scan_id)
        print_good("Scan ID #{scan_id} successfully launched. The Scan UUID is " + launch["scan_uuid"])
      end
         
      def cmd_nessus_scan_pause(*args)
        if args[0] == "-h"
          print_status("nessus_scan_pause <scan id>")
          print_status("Example:> nessus_scan_pause f0eabba3-4065-7d54-5763-f191e98eb0f7f9f33db7e75a06ca")
          print_status()
          print_status("Pauses a running scan")
          print_status("Use nessus_scan_status to list all available scans")
          return
        end
        if !nessus_verify_token
          return
        end
        case args.length
        when 1
          sid = args[0]
        else
          print_status("Usage: ")
          print_status("nessus_scan_pause <scan id>")
          print_status("Use nessus_scan_status to list all available scans")
          return
        end
        pause = @n.scan_pause(sid)
        if pause["error"]
          print_error "Invalid scan ID"
        else
          print_status("#{sid} has been paused")
        end
      end
         
      def cmd_nessus_scan_resume(*args)
        if args[0] == "-h"
          print_status("nessus_scan_resume <scan id>")
          print_status("Example:> nessus_scan_resume f0eabba3-4065-7d54-5763-f191e98eb0f7f9f33db7e75a06ca")
          print_status()
          print_status("resumes a running scan")
          print_status("Use nessus_scan_status to list all available scans")
          return
        end
        if !nessus_verify_token
          return
        end
        case args.length
        when 1
          sid = args[0]
        else
          print_status("Usage: ")
          print_status("nessus_scan_resume <scan id>")
          print_status("Use nessus_scan_status to list all available scans")
          return
        end
        resume = @n.scan_resume(sid)
        if resume["error"]
          print_error "Invalid scan ID"
        else
          print_status("#{sid} has been resumed")
        end
      end
         
      def cmd_nessus_report_hosts(*args)
        if args[0] == "-h"
          print_status("nessus_report_hosts <report id>")
          print_status("Example:> nessus_report_hosts f0eabba3-4065-7d54-5763-f191e98eb0f7f9f33db7e75a06ca")
          print_status()
          print_status("Returns all the hosts associated with a scan and details about their vulnerabilities")
          print_status("Use nessus_report_list to list all available scans")
          return
        end
        if !nessus_verify_token
          return
        end
        case args.length
        when 1
          rid = args[0]
        else
          print_status("Usage: ")
          print_status("nessus_report_hosts <report id>")
          print_status("Use nessus_report_list to list all available reports")
          return
        end
        tbl = Rex::Ui::Text::Table.new(
          'Columns' => [
            'Hostname',
            'Severity',
            'Sev 0',
            'Sev 1',
            'Sev 2',
            'Sev 3',
            'Current Progress',
            'Total Progress'
          ])
        hosts=@n.report_hosts(rid)
        hosts.each {|host|
        tbl << [ host['hostname'], host['severity'], host['sev0'], host['sev1'], host['sev2'], host['sev3'], host['current'], host['total'] ]
        }
        print_good("Report Info")
        print_good "\n"
        print_line tbl.to_s
        print_status("You can:")
        print_status("Get information from a particular host: nessus_report_host_ports <hostname> <report id>")
      end
         
      def cmd_nessus_report_vulns(*args)
        if args[0] == "-h"
          print_status("nessus_report_vulns <report id>")
          print_status("Example:> nessus_report_vulns f0eabba3-4065-7d54-5763-f191e98eb0f7f9f33db7e75a06ca")
          print_status()
          print_status("Returns all the vulns associated with a scan and details about hosts and their vulnerabilities")
          print_status("Use nessus_report_list to list all available scans")
          return
        end
        if !nessus_verify_token
          return
        end
        case args.length
        when 1
          rid = args[0]
        else
          print_status("Usage: ")
          print_status("nessus_report_vulns <report id>")
          print_status("Use nessus_report_vulns to list all available reports")
          return
        end
        tbl = Rex::Ui::Text::Table.new(
          'Columns' => [
            'Hostname',
            'Port',
            'Proto',
            'Sev',
            'PluginID',
            'Plugin Name'
          ])
        print_status("Grabbing all vulns for report #{rid}")
        hosts=@n.report_hosts(rid)
        hosts.each do |host|
        ports=@n.report_host_ports(rid, host['hostname'])
        ports.each do |port|
          details=@n.report_host_port_details(rid, host['hostname'], port['portnum'], port['protocol'])
            details.each do |detail|
              tbl << [host['hostname'], port['portnum'], port['protocol'], detail['severity'], detail['pluginID'], detail['pluginName'] ]
            end
          end
        end
        print_good("Report Info")
        print_line
        print_line tbl.to_s
        print_status("You can:")
        print_status("Get information from a particular host: nessus_report_host_ports <hostname> <report id>")
      end
         
      def cmd_nessus_report_host_ports(*args)
        if args[0] == "-h"
          print_status("nessus_report_host_ports <hostname> <report id>")
          print_status("Example:> nessus_report_host_ports 192.168.1.250 f0eabba3-4065-7d54-5763-f191e98eb0f7f9f33db7e75a06ca")
          print_status()
          print_status("Returns all the ports associated with a host and details about their vulnerabilities")
          print_status("Use nessus_report_hosts to list all available hosts for a report")
        end
        if !nessus_verify_token
          return
        end
        case args.length
        when 2
          host = args[0]
          rid = args[1]
        else
          print_status("Usage: ")
          print_status("nessus_report_host_ports <hostname> <report id>")
          print_status("Use nessus_report_list to list all available reports")
          return
        end
        tbl = Rex::Ui::Text::Table.new(
          'Columns' => [
            'Port',
            'Protocol',
            'Severity',
            'Service Name',
            'Sev 0',
            'Sev 1',
            'Sev 2',
            'Sev 3'
          ])
        ports=@n.report_host_ports(rid, host)
        ports.each {|port|
        tbl << [ port['portnum'], port['protocol'], port['severity'], port['svcname'], port['sev0'], port['sev1'], port['sev2'], port['sev3'] ]
        }
        print_good("Host Info")
        print_good "\n"
        print_line tbl.to_s
        print_status("You can:")
        print_status("Get detailed scan infromation about a specfic port: nessus_report_host_detail <hostname> <port> <protocol> <report id>")
      end

      def cmd_nessus_report_host_detail(*args)
        if args[0] == "-h"
          print_status("nessus_report_host_detail <hostname> <port> <protocol> <report id>")
          print_status("Example:> nessus_report_host_ports 192.168.1.250 445 tcp f0eabba3-4065-7d54-5763-f191e98eb0f7f9f33db7e75a06ca")
          print_status()
          print_status("Returns all the vulns associated with a port for a specific host")
          print_status("Use nessus_report_host_ports to list all available ports for a host")
          return
        end
        if !nessus_verify_token
          return
        end
        case args.length
        when 4
          host = args[0]
          port = args[1]
          prot = args[2]
          rid = args[3]
        else
          print_status("Usage: ")
          print_status("nessus_report_host_detail <hostname> <port> <protocol> <report id>")
          print_status("Use nessus_report_host_ports to list all available ports")
          return
        end
        tbl = Rex::Ui::Text::Table.new(
          'Columns' => [
            'Port',
            'Severity',
            'PluginID',
            'Plugin Name',
            'CVSS2',
            'Exploit?',
            'CVE',
            'Risk Factor',
            'CVSS Vector'
          ])
        details=@n.report_host_port_details(rid, host, port, prot)
        details.each {|detail|
        tbl << [ detail['port'], detail['severity'], detail['pluginID'], detail['pluginName'], detail['cvss_base_score'] || 'none',
               detail['exploit_available'] || '.', detail['cve'] || '.', detail['risk_factor'] || '.', detail['cvss_vector'] || '.' ]
        }
        print_good("Port Info")
        print_good "\n"
        print_line tbl.to_s
      end

      def cmd_nessus_scan_pause_all(*args)
        scan_ids = Array.new
        if args[0] == "-h"
          print_status("nessus_scan_pause_all")
          print_status("Example:> nessus_scan_pause_all")
          print_status()
          print_status("Pauses all currently running scans")
          print_status("Use nessus_scan_list to list all running scans")
          return
        end
        if !nessus_verify_token
          return
        end
        list = @n.scan_list
        list.each { |scan|
        if scan["status"] == "running"
          scan_ids << scan["id"]
        end
        }
        if scan_ids.length > 0
          scan_ids.each { |scan_id|
          @n.scan_pause(scan_id)
          }
          print_status("All scans have been paused")
        else
          print_error("No running scans")
        end
      end

      def cmd_nessus_scan_stop(*args)
        if args[0] == "-h"
          print_status("nessus_scan_stop <scan id>")
          print_status("Example:> nessus_scan_stop f0eabba3-4065-7d54-5763-f191e98eb0f7f9f33db7e75a06ca")
          print_status()
          print_status("Stops a currently running scans")
          print_status("Use nessus_scan_list to list all running scans")
          return
        end
        if !nessus_verify_token
          return
        end
        case args.length
        when 1
          sid = args[0]
        else
          print_status("Usage: ")
          print_status("nessus_scan_stop <scan id>")
          print_status("Use nessus_scan_status to list all available scans")
          return
        end
        stop = @n.scan_stop(sid)
        if stop["error"]
          print_error "Invalid scan ID"
        else
          print_status("#{sid} has been stopped")
        end
      end

      def cmd_nessus_scan_stop_all(*args)
        scan_ids = Array.new
        if args[0] == "-h"
          print_status("nessus_scan_stop_all")
          print_status("Example:> nessus_scan_stop_all")
          print_status()
          print_status("stops all currently running scans")
          print_status("Use nessus_scan_list to list all running scans")
          return
        end
        if !nessus_verify_token
          return
        end
        list = @n.scan_list
        list.each { |scan|
        if scan["status"] == "running" || scan["status"] == "paused"
          scan_ids << scan["id"]
        end
        }
        if scan_ids.length > 0
          scan_ids.each { |scan_id|
          @n.scan_stop(scan_id)
          }
          print_status("All scans have been stopped")
        else
          print_error("No running or paused scans to be stopped")
        end
      end

      def cmd_nessus_scan_resume_all(*args)
        scan_ids = Array.new
        if args[0] == "-h"
          print_status("nessus_scan_resume_all")
          print_status("Example:> nessus_scan_resume_all")
          print_status()
          print_status("resumes all currently running scans")
          print_status("Use nessus_scan_list to list all running scans")
          return
        end
        if !nessus_verify_token
          return
        end
        list = @n.scan_list
        list.each { |scan|
        if scan["status"] == "paused"
          scan_ids << scan["id"]
        end
        }
        if scan_ids.length > 0
          scan_ids.each { |scan_id|
          @n.scan_resume(scan_id)
          }
          print_status("All scans have been resumed")
        else
          print_error("No running scans to be resumed")
        end
      end

      def cmd_nessus_user_add(*args)
        if args[0] == "-h"
          print_status("nessus_user_add <username> <password> <permissions> <type>")
          print_status("Permissions are 32, 64, and 128")
          print_status("Type can be either local or LDAP")
          print_status("Example:> nessus_user_add msf msf 16 local")
          print_status("You need to be an admin in order to add accounts")
          print_status("Use nessus_user_list to list all users")
          return
        end
        if !nessus_verify_token
          return
        end
        if !@n.is_admin
          print_error("Your Nessus user is not an admin")
          return
        end
        case args.length
        when 4
          user = args[0]
          pass = args[1]
          permissions = args[2]
          type = args[3]
        else
          print_status("Usage")
          print_status("nessus_user_add <username> <password> <permissions> <type>")
          return
        end
        add = @n.user_add(user,pass,permissions,type)
        if add["id"]
          print_good("#{user} created successfully")
        else
          print_error(add.to_s)
        end
      end

      def cmd_nessus_user_del(*args)
        if args[0] == "-h"
          print_status("nessus_user_del <User ID>")
          print_status("Example:> nessus_user_del 10")
          print_status()
          print_status("This command can only delete non admin users. You must be an admin to delete users.")
          print_status("Use nessus_user_list to list all users with their corresponding user IDs")
          return
        end
        if !nessus_verify_token
          return
        end
        if !@n.is_admin
          print_error("Your Nessus user is not an admin")
          return
        end
        case args.length
        when 1
          user_id = args[0]
        else
          print_status("Usage: ")
          print_status("nessus_user_del <User ID>")
          print_status("This command can only delete non admin users")
          return
        end
        del = @n.user_delete(user_id)
        status = del.to_s
        if status == "200"
          print_good("User account having user ID #{user_id} deleted successfully")
        elsif status == "403"
          print_error("You do not have permission to delete the user account having user ID #{user_id}")
        elsif status == "404"
          print_error("User account having user ID #{user_id} does not exist")
        elsif status == "409"
          print_error("You cannot delete your own account")
        elsif status == "500"
          print_error("The server failed to delete the user account having user ID #{user_id}")
        else
          print_error("Unknown problem occured by deleting the user account having user ID #{user_id}.")
        end
      end

      def cmd_nessus_user_passwd(*args)
        if args[0] == "-h"
          print_status("nessus_user_passwd <User ID> <New Password>")
          print_status("Example:> nessus_user_passwd 10 mynewpassword")
          print_status("Changes the password of a user. You must be an admin to change passwords.")
          print_status("Use nessus_user_list to list all users with their corresponding user IDs")
          return
        end
        if !nessus_verify_token
          return
        end
        if !@n.is_admin
          print_error("Your Nessus user is not an admin")
          return
        end
        case args.length
        when 2
          user_id = args[0]
          pass = args[1]
        else
          print_status("Usage: ")
          print_status("nessus_user_passwd <User ID> <New Password>")
          print_status("Use nessus_user_list to list all users with their corresponding user IDs")
          return
        end
        pass = @n.user_chpasswd(user_id,pass)
        status = pass.to_s
        if status == "200"
          print_good("Password of account having user ID #{user_id} changed successfully")
        elsif status == "400"
          print_error("Password is too short")
        elsif status == "403"
          print_error("You do not have the permission to change password for the user having user ID #{user_id}")
        elsif status == "404"
          print_error("User having user ID #{user_id} does not exist")
        elsif status == "500"
          print_error("Nessus server failed to changed the user password")
        else
          print_error("Unknown problem occured while changing the user password")
        end
      end

      def cmd_nessus_admin(*args)
        if args[0] == "-h"
          print_status("nessus_admin")
          print_status("Example:> nessus_admin")
          print_status()
          print_status("Checks to see if the current user is an admin")
          print_status("Use nessus_user_list to list all users")
          return
        end
        if !nessus_verify_token
          return
        end
        if !@n.is_admin
          print_error("Your Nessus user is not an admin")
        else
          print_good("Your Nessus user is an admin")
        end
      end

      def cmd_nessus_plugin_list(*args)
        if args[0] == "-h"
          print_status("nessus_plugin_list <Family ID>")
          print_status("Example:> nessus_plugin_list 10")
          print_status()
          print_status("Returns a list of all plugins in that family.")
          print_status("Use nessus_family_list to display all the plugin families along with their corresponding family IDs")
          return
        end
        if !nessus_verify_token
          return
        end
        case args.length
        when 1
          family_id = args[0]
        else
          print_status("Usage: ")
          print_status("nessus_plugin_list <Family ID>")
          print_status("Use nessus_family_list to display all the plugin families along with their corresponding family IDs")
          return
        end
        tbl = Rex::Ui::Text::Table.new(
          'Columns' => [
            'Plugin ID',
            'Plugin Name'
          ])
        list = @n.list_plugins(family_id)
        list["plugins"].each {|plugin|
        tbl << [ plugin["id"], plugin["name"] ]
        }
        print_good("Plugin Family Name: " + list["name"])
        print_line tbl.to_s
      end

      def cmd_nessus_policy_list(*args)
        if args[0] == "-h"
          print_status("nessus_policy_list")
          print_status("Example:> nessus_policy_list")
          print_status()
          print_status("Lists all policies on the server")
          return
        end
        if !nessus_verify_token
          return
        end
        list=@n.list_policies

        unless list["policies"]
          print_error("No policies found")
          return
        end

        tbl = Rex::Ui::Text::Table.new(
          'Columns' => [
            'Policy ID',
            'Name',
            'Policy UUID'
          ])
        list["policies"].each { |policy|
        tbl << [ policy["id"], policy["name"], policy["template_uuid"] ]
        }
        print_line tbl.to_s
      end

      def cmd_nessus_policy_del(*args)
        if args[0] == "-h"
          print_status("nessus_policy_del <policy ID>")
          print_status("Example:> nessus_policy_del 1")
          print_status()
          print_status("Must be an admin to del policies.")
          print_status("use nessus_policy_list to list all policies")
          return
        end
        if !nessus_verify_token
          return
        end
        if !@n.is_admin
          print_error("Your Nessus user is not an admin")
          return
        end
        case args.length
        when 1
          policy_id = args[0]
        else
          print_status("Usage: ")
          print_status("nessus_policy_del <policy ID>")
          print_status("nessus_policy_list to find the id.")
          return
        end
        del = @n.policy_delete(policy_id)
        status = del.to_s
        if status == "200"
          print_good("Policy ID #{policy_id} successfully deleted")
        elsif status == "403"
          print_error("You do not have permission to delete policy ID #{policy_id}")
        elsif status == "404"
          print_error("Policy ID #{policy_id} does not exist")
        elsif status == "405"
          print_error("Policy ID #{policy_id} is currently in use and cannot be deleted")
        else
          print_error("Unknown problem occured by deleting the user account having user ID #{user_id}.")
        end
      end

      def cmd_nessus_plugin_details(*args)
        if args[0] == "-h"
          print_status("nessus_plugin_details <Plugin ID>")
          print_status("Example:> nessus_plugin_details 10264")
          print_status()
          print_status("Returns details on a particular plugin.")
          print_status("Use nessus_plugin_list to list all plugins and their corresponding plugin IDs belonging to a particular plugin family.")
          return
        end
        if !nessus_verify_token
          return
        end
        case args.length
        when 1
          plugin_id = args[0]
        else
          print_status("Usage: ")
          print_status("nessus_plugin_details <Plugin ID>")
          print_status("Use nessus_plugin_list to list all plugins and their corresponding plugin IDs belonging to a particular plugin family.")
          return
        end
        tbl = Rex::Ui::Text::Table.new(
          'Columns' => [
            'Reference',
            'Value'
          ])
        begin
          list = @n.plugin_details(plugin_id)
        rescue ::Exception => e
          if e.message =~ /unexpected token/
            print_error("No plugin info found")
            return
          else
            raise e
          end
        end
        list["attributes"].each { |attrib|
        tbl << [ attrib["attribute_name"], attrib["attribute_value"] ]
        }
        print_good("Plugin Name: " + list["name"])
        print_good("Plugin Family: " + list["family_name"])
        print_line tbl.to_s
      end

      def cmd_nessus_report_del(*args)
        if args[0] == "-h"
          print_status("nessus_report_del <reportname>")
          print_status("Example:> nessus_report_del f0eabba3-4065-7d54-5763-f191e98eb0f7f9f33db7e75a06ca")
          print_status()
          print_status("Must be an admin to del reports.")
          print_status("Use nessus_report_list to list all reports")
          return
        end
        if !nessus_verify_token
          return
        end
        if !@n.is_admin
          print_error("Your Nessus user is not an admin")
          return
        end
        case args.length
        when 1
          rid = args[0]
        else
          print_status("Usage: ")
          print_status("nessus_report_del <report ID>")
          print_status("nessus_report_list to find the id.")
          return
        end
        del = @n.report_del(rid)
        status = del.root.elements['status'].text
        if status == "OK"
          print_good("Report #{rid} has been deleted")
        else
          print_error("Report #{rid} was not deleted")
        end
      end

      def cmd_nessus_server_prefs(*args)
        if args[0] == "-h"
          print_status("nessus_server_prefs")
          print_status("Example:> nessus_server_prefs")
          print_status()
          print_status("Returns a long list of server prefs.")
          return
        end
        if !nessus_verify_token
          return
        end
        if !@n.is_admin
          print_error("Your Nessus user is not an admin")
          return
        end
        tbl = Rex::Ui::Text::Table.new(
          'Columns' => [
            'Name',
            'Value'
          ])
        prefs = @n.server_prefs
        prefs.each {|pref|
        tbl << [ pref['name'], pref['value'] ]
        }
        print_good("Nessus Server Pref List")
        print_good "\n"
        print_line tbl.to_s + "\n"
      end

      def cmd_nessus_plugin_prefs(*args)
        if args[0] == "-h"
          print_status("nessus_plugin_prefs")
          print_status("Example:> nessus_plugin_prefs")
          print_status()
          print_status("Returns a long list of plugin prefs.")
          return
        end
        if !nessus_verify_token
          return
        end
        if !@n.is_admin
          print_error("Your Nessus user is not an admin")
          return
        end
        tbl = Rex::Ui::Text::Table.new(
          'Columns' => [
            'Name',
            'Value',
            'Type'
          ])
        prefs = @n.plugin_prefs
        prefs.each {|pref|
        tbl << [ pref['prefname'], pref['prefvalues'], pref['preftype'] ]
        }
        print_good("Nessus Plugins Pref List")
        print_good "\n"
        print_line tbl.to_s
      end
    end

    def initialize(framework, opts)
      super
      add_console_dispatcher(ConsoleCommandDispatcher)
      print_status("Nessus Bridge for Metasploit")
      print_good("Type %bldnessus_help%clr for a command listing")
    end

    def cleanup
      remove_console_dispatcher('Nessus')
    end
  end
end
