require 'active_support/all'
require 'aws-sdk-core'
require 'fluent/input'
require "json"
require 'myslog'
require 'yaml'

module Fluent
  class AuroraSlowqueryLog < Input
    # First, register the plugin. NAME is the name of this plugin
    # and identifies the plugin in the configuration file.
    Fluent::Plugin.register_input('aurora_slowquerylog', self)

    # config_param defines a parameter. You can refer a parameter via @port instance variable
    # :default means this parameter is optional
    config_param :tag, :string                    # tag.child_tag
    config_param :db_instance_identifier, :string # rds-instance-id
    config_param :region, :string                 # us-east-1
    config_param :log_file_name, :string          # slowquery/mysql-slowquery.log
    config_param :aurora_state_file, :string      #/tmp/marker_state

    # Following configs are necessary if you don't use IAM instance profile
    config_param :log_fetch_interval, :time, :default => 60
    config_param :aws_access_key_id, :string, default: nil
    config_param :aws_secret_access_key, :string, default: nil
    config_param :filename_contains, :string, default: 'mysql-slowquery.log'

    def initialize
      super
      @current_slowlog = nil
      @previous_slowlog = nil
    end

    # This method is called before starting.
    # 'conf' is a Hash that includes configuration parameters.
    # If the configuration is invalid, raise Fluent::ConfigError.
    def configure(conf)
      super
    end

    # This method is called when starting.
    # Open sockets or files and create a thread here.
    def start
      super
      @stop_flag = false
      $log.debug 'Start aurora log collection thread'
      @thread = Thread.new(&method(:thread_main))
    end

    # This method is called when shutting down.
    def shutdown
      super
      @stop_flag = true
      $log.debug 'Waiting for thread to finish'
      @thread.join
    end

    def thread_main
      until @stop_flag
        begin
          fetch_aurora_slow_log
        rescue => e
          log.error 'unexpected error', :error => e.message, :error_class => e.class
          log.error_backtrace e.backtrace
        end
        sleep @log_fetch_interval
      end
    end

    def create_rds_client
      @rds_client = if @aws_access_key_id && @aws_secret_access_key
                      Aws::RDS::Client.new(
                        region: @region,
                        access_key_id: @aws_access_key_id,
                        secret_access_key: @aws_secret_access_key
                      )
                    else # Use IAM Profile
                      Aws::RDS::Client.new(region: @region)
                    end
    end

    def fetch_aurora_slow_log
      create_rds_client
      fetch_recent_slowlogs
      if File.exist?(@aurora_state_file)
        state = load_state
        if slowlog_rotated?(state)
          if state["additional_data_pending"]
            fetch_and_emit_log(@previous_slowlog, state["marker"],true)
          else
            fetch_and_emit_log(@previous_slowlog, state["marker"],false)
          end
        else
          fetch_and_emit_log(@current_slowlog, state["marker"],true)
        end
      else
        fetch_and_emit_log(@current_slowlog, false, true)
      end
    end

    def fetch_and_emit_log(log_file_name,marker,save)
      if save
        if marker
          fetched_file = @rds_client.download_db_log_file_portion(
            db_instance_identifier: @db_instance_identifier,
            log_file_name: log_file_name,
            marker: marker)
          save_state(fetched_file)
          records = parse_fetched_file(fetched_file)
          emit_slowlogs(records)
        else
          fetched_file = @rds_client.download_db_log_file_portion(
            db_instance_identifier: @db_instance_identifier,
            log_file_name: log_file_name)
          save_state(fetched_file)
          records = parse_fetched_file(fetched_file)
          emit_slowlogs(records)
        end
      else # Executed when log rotation occurs without pending data
        fetched_file = @rds_client.download_db_log_file_portion(
          db_instance_identifier: @db_instance_identifier,
          log_file_name: log_file_name,
          marker: marker)
        system("rm #{@aurora_state_file}")
        records = parse_fetched_file(fetched_file)
        emit_slowlogs(records)
      end
    end

    def parse_fetched_file(fetched_file)
      parsed_log_data= parse_query(fetched_file)
      exclude_useless_sql(parsed_log_data)
    end

    def parse_query(fetched_file)
      myslog = MySlog.new
      myslog.parse(fetched_file.log_file_data)
    end

    def load_state
      begin
        YAML.load_file(@aurora_state_file)
      rescue SystemCallError => e
        puts %Q(class=[#{e.class}] message=[#{e.message}])
      rescue IOError => e
        puts %Q(class=[#{e.class}] message=[#{e.message}])
      end
    end

    def slowlog_rotated?(state)
      if @previous_slowlog == state["previous_slowlog"]
        false
      else
        true
      end
    end

    def fetch_recent_slowlogs
      log_files = []
      unix_time_2hours_ago = (2.hours.ago.to_f * 1000).floor

      @rds_client.describe_db_log_files(db_instance_identifier: @db_instance_identifier, filename_contains: @filename_contains, file_last_written: unix_time_2hours_ago).each do |page|
        page.describe_db_log_files.each do |f|
          log_files << f
        end
      end

      sorted_slow_log_files = log_files.sort_by do |f|
        f.last_written
      end

      if sorted_slow_log_files.length >= 2
        current,previous = sorted_slow_log_files[-1], sorted_slow_log_files[-2]
        @current_slowlog = current.log_file_name
        @previous_slowlog = previous.log_file_name
      elsif sorted_slow_log_files.length >= 1
        current = sorted_slow_log_files[-1]
        @current_slowlog = current.log_file_name
      else
        raise "There is no slowlog. Please set log_output=FILE"
      end
    end

    def save_state(fetched_file)
      open(@aurora_state_file, 'w') do |f|
        state_keys={}
        state_keys["marker"] = fetched_file.marker
        state_keys["additional_data_pending"] = fetched_file.additional_data_pending
        state_keys["current_slowlog"] = @current_slowlog
        state_keys["previous_slowlog"] = @previous_slowlog
        YAML.dump(state_keys,f)
      end
    end

    # Exclude useless SQL queries
    def exclude_useless_sql(parsed_log_data)
      responses = []
      parsed_log_data.each do |record|
        if m = record[:sql].match(/^\/rdsdbbin\/oscar\/bin\/mysqld/)
          next
        elsif m = record[:sql].match(/^(.+); \/rdsdbbin\/oscar\/bin\/mysqld,.+ Argument/)
          responses << record
          responses.last[:sql] = m[1]
        elsif m = record[:sql].match(/^use .+; SET timestamp=\d+; (.+)/)
          responses << record
          responses.last[:sql] = m[1]
        elsif m = record[:sql].match(/^SET timestamp=\d+; (.+)/)
          responses << record
          responses.last[:sql] = m[1]
        else
          responses << record
        end
      end
      responses
    end

    def emit_slowlogs(records)
      es = MultiEventStream.new
      records.each do |record|
        es.add(record[:date], record)
      end
      unless es.empty?
        begin
          router.emit_stream(@tag, es)
        rescue
        end
      end
    end
  end
end
