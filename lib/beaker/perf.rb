module Beaker
  # The Beaker Perf class. A single instance is created per Beaker run.
  class Perf

    PERF_PACKAGES = ['sysstat']
    # SLES does not treat sysstat as a service that can be started
    PERF_SUPPORTED_PLATFORMS = /debian|ubuntu|redhat|centos|oracle|scientific|fedora|el|eos|cumulus|sles/
    PERF_START_PLATFORMS     = /debian|ubuntu|redhat|centos|oracle|scientific|fedora|el|eos|cumulus/

    # Create the Perf instance and runs setup_perf_on_host on all hosts if --collect-perf-data
    # was used as an option on the Baker command line invocation. Instances of this class do not
    # hold state and its methods are helpers for remotely executing tasks for performance data
    # gathering with sysstat/sar
    #
    # @param [Array<Host>] hosts All from the configuration
    # @param [Hash] options Options to alter execution
    # @return [void]
    def initialize( hosts, options )
      @hosts = hosts
      @options = options
      @logger = options[:logger]
      @perf_timestamp = Time.now
      @hosts.map { |h| setup_perf_on_host(h) }
      @perf_data = Hash.new()
    end

    # Install sysstat if required and perform any modifications needed to make sysstat work.
    # @param [Host] host The host we are working with
    # @return [void]
    def setup_perf_on_host(host)
      @logger.perf_output("Setup perf on host: " + host)
      # Install sysstat if required
      if host['platform'] =~ PERF_SUPPORTED_PLATFORMS
        PERF_PACKAGES.each do |pkg|
          if not host.check_for_package pkg
            host.install_package pkg
          end
        end
      else
        @logger.perf_output("Perf (sysstat) not supported on host: " + host)
      end

      if host['platform'] =~ /debian|ubuntu|cumulus/
        @logger.perf_output("Modify /etc/default/sysstat on Debian and Ubuntu platforms")
        host.exec(Command.new('sed -i s/ENABLED=\"false\"/ENABLED=\"true\"/ /etc/default/sysstat'))
      elsif host['platform'] =~ /sles/
        @logger.perf_output("Creating symlink from /etc/sysstat/sysstat.cron to /etc/cron.d")
        host.exec(Command.new('ln -s /etc/sysstat/sysstat.cron /etc/cron.d'),:acceptable_exit_codes => [0,1])
      end
      if @options[:collect_perf_data] =~ /aggressive/
        @logger.perf_output("Enabling aggressive sysstat polling")
        if host['platform'] =~ /debian|ubuntu/
          host.exec(Command.new('sed -i s/5-55\\\/10/*/ /etc/cron.d/sysstat'))
        elsif host['platform'] =~ /centos|el|fedora|oracle|redhats|scientific/
          host.exec(Command.new('sed -i s/*\\\/10/*/ /etc/cron.d/sysstat'))
        end
      end
      if host['platform'] =~ PERF_START_PLATFORMS # SLES doesn't need this step
        host.exec(Command.new('service sysstat start'))
      end
    end

    # Iterate over all hosts, calling get_perf_data
    # @return [void]
    def print_perf_info()
      @perf_end_timestamp = Time.now
      @perf_data = get_perf_data(@hosts, @perf_timestamp, @perf_end_timestamp)
      if (defined? @options[:graphite_server] and not @options[:graphite_server].nil?) and
         (defined? @options[:graphite_perf_data] and not @options[:graphite_perf_data].nil?)
        export_perf_data_to_graphite(@hosts, @perf_data)
      end
      if defined? @options[:save_perf_data]
        save_perf_data(@perf_data)
      end
    end

    # If host is a supported (ie linux) platform, generate a performance report
    # @param [Hosts] hosts The hosts we are working with
    # @param [Time] perf_start The beginning time for the SAR report
    # @param [Time] perf_end   The ending time for the SAR report
    # @return [void]  The report is sent to the logging output
    def get_perf_data(hosts, perf_start, perf_end)
      perf_data = Hash.new()
      hosts.each do |host|
        @logger.perf_output("Getting perf data for host: " + host)
        if host['platform'] =~ PERF_SUPPORTED_PLATFORMS # All flavours of Linux
          if not @options[:collect_perf_data] =~ /aggressive/
            host.exec(Command.new("sar -A -s #{perf_start.strftime("%H:%M:%S")} -e #{perf_end.strftime("%H:%M:%S")}"),:acceptable_exit_codes => [0,1,2])
          end
          perf_data[host['vmhostname']] = JSON.parse(host.exec(Command.new("sadf -j -- -A"),:silent => true).stdout)
        else
          @logger.perf_output("Perf (sysstat) not supported on host: " + host)
        end
      end
      return perf_data
    end

    # Saves the performance report to disk in the JSON format
    # @param [Hash] perf_data The unprocessed performance data
    # @param [String] perf_file This is the target path to save the performance data as a JSON file
    def save_perf_data(perf_data, perf_file = File.join(@options[:log_dated_dir], 'perf_data.json'))
      File.open(perf_file, 'w') do |f|
        f.write(perf_data.to_json)
      end
      @logger.perf_output("Saved perf data to " + perf_file)
    end
    # Send performance report numbers to an external Graphite instance
    # @param [Hosts] hosts The host we are working with
    # @param [Hash] perf_data The unprocessed performance data
    # @return [void]  The report is sent to the logging output
    def export_perf_data_to_graphite(hosts, perf_data)
      @logger.perf_output("Sending data to Graphite server: " + @options[:graphite_server])

      hosts.each do |host|
        hostname = host['vmhostname'].split('.')[0]
        perf_data[host['vmhostname']]['sysstat']['hosts'].each do |host|
          host['statistics'].each do |poll|
            timestamp = DateTime.parse(poll['timestamp']['date'] + ' ' + poll['timestamp']['time']).to_time.to_i

            poll.keys.each do |stat|
              case stat
                when 'cpu-load-all'
                  poll[stat].each do |s|
                    s.keys.each do |k|
                      next if k == 'cpu'

                      socket = TCPSocket.new(@options[:graphite_server], 2003)
                      socket.puts "#{@options[:graphite_perf_data]}.#{hostname}.cpu.#{s['cpu']}.#{k} #{s[k]} #{timestamp}"
                      socket.close
                    end
                  end

                when 'memory'
                  poll[stat].keys.each do |s|
                    socket = TCPSocket.new(@options[:graphite_server], 2003)
                    socket.puts "#{@options[:graphite_perf_data]}.#{hostname}.memory.#{s} #{poll[stat][s]} #{timestamp}"
                    socket.close
                  end
              end
            end
          end
      end
    end
  end
end
end

