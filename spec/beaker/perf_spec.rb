require 'spec_helper'

module Beaker
  describe Perf do

    context "When a Perf object is created" do
      it 'creates a new Perf object' do
        hosts = Array.new
        options = Hash.new
        options[:log_level] = :debug
        my_logger = Beaker::Logger.new(options)
        options[:logger] = my_logger
        perf = Perf.new( hosts, options )
        expect( perf ).to be_a_kind_of Perf
      end

      before(:each) do
        @options = make_opts
        @options[:collect_perf_data] = true
        @options[:log_level] = :debug
        @options[:color] = false
        @my_io = StringIO.new
        @my_logger = Beaker::Logger.new(@options)
        @my_logger.add_destination(@my_io)
        @options[:logger] = @my_logger
        @options[:log_dated_dir] = 'test_perf_data_dir'
      end

      it 'creates a new Perf object with a single host, :collect_perf_data = true' do
        hosts = [ make_host("myHost", @options) ]
        hosts.each { |host| host['platform'] = "centos-6-x86_64" }
        @my_logger.remove_destination(STDOUT)
        perf = Perf.new( hosts, @options )
        expect( perf ).to be_a_kind_of Perf
        expect(@my_io.string).to match(/Setup perf on host: myHost/)
      end

      it 'creates a new Perf object with multiple hosts, :collect_perf_data = true' do
        hosts = [ make_host("myHost", @options), make_host("myOtherHost", @options) ]
        hosts.each { |host| host['platform'] = "centos-6-x86_64" }
        @my_logger.remove_destination(STDOUT)
        perf = Perf.new( hosts, @options )
        expect( perf ).to be_a_kind_of Perf
        expect(@my_io.string).to match(/Setup perf on host: myHost*\nSetup perf on host: myOtherHost/)
      end

      it 'creates a new Perf object with multiple hosts, :collect_perf_data = true, SLES' do
        hosts = [ make_host("myHost", @options), make_host("myOtherHost", @options) ]
        hosts[0]['platform'] = "centos-6-x86_64"
        hosts[1]['platform'] = "sles-11-x86_64"
        @my_logger.remove_destination(STDOUT)
        perf = Perf.new( hosts, @options )
        expect( perf ).to be_a_kind_of Perf
        expect(@my_io.string).to match(/Setup perf on host: myHost\nSetup perf on host: myOtherHost/)
      end
    end

    context "When testing is finished, :collect_perf_data = true" do
      before(:each) do
        @options = make_opts
        @options[:collect_perf_data] = true
        @options[:log_level] = :debug
        @options[:color] = false
        @hosts = [ make_host("myHost", @options), make_host("myOtherHost", @options) ]
        @my_io = StringIO.new
        @my_logger = Beaker::Logger.new(@options)
        @my_logger.add_destination(@my_io)
        @options[:logger] = @my_logger
      end

      it "Does the Right Thing on Linux hosts" do
        @hosts[0]['platform'] = "centos-6-x86_64"
        @my_logger.remove_destination(STDOUT)
        perf = Perf.new( @hosts, @options )
        expect( perf ).to be_a_kind_of Perf
        perf.print_perf_info
        expect(@my_io.string).to match(/Setup perf on host: myHost\nSetup perf on host: myOtherHost\nPerf \(sysstat\) not supported on host: myOtherHost\nGetting perf data for host: myHost\nGetting perf data for host: myOtherHost\nPerf \(sysstat\) not supported on host: myOtherHost/)
      end

      it "Does the Right Thing on non-Linux hosts" do
        @hosts[0]['platform'] = "windows"
        @my_logger.remove_destination(STDOUT)
        perf = Perf.new( @hosts, @options )
        expect( perf ).to be_a_kind_of Perf
        perf.print_perf_info
        expect(@my_io.string).to match(/Setup perf on host: myHost\nPerf \(sysstat\) not supported on host: myHost\nSetup perf on host: myOtherHost\nPerf \(sysstat\) not supported on host: myOtherHost\nGetting perf data for host: myHost\nPerf \(sysstat\) not supported on host: myHost\nGetting perf data for host: myOtherHost\nPerf \(sysstat\) not supported on host: myOtherHost/)
      end
    end
  end
end
