#!/usr/bin/env ruby
require 'couchrest'
require 'restclient'
require 'json'

class ScenarioService
  def initialize host
    host or raise "Please supply studio host: 'server=<host>'"
    @studio = "http://#{host}"
    @scenario_server = "http://#{host}:8099/api/1"
  end

  # params may be provided for search and paging
  def get_scenarios params=nil
    JSON(RestClient.get "#{@studio}/scenarios?#{params}")['results']
  end

  # id is scenario id in studio db
  def offline_pcap id
    msl = RestClient.get "#{@studio}/scenarios/download?id=#{id}"
    RestClient.post "#{@scenario_server}/offline_pcap", { :msl => msl }
  rescue Exception => e
    puts "Error #{id}: #{e.inspect}"
  end

  # pcap is path to pcap file
  def create_scenario pcap
    bin = File.open(pcap,"rb") {|io| io.read}
    RestClient.post "#{@scenario_server}/create_scenario", { :pcap => bin, :read_filter => 'tcp or udp and not icmp' }
  rescue Exception => e
    puts "Error #{pcap}: #{e.inspect}"
  end

  def upload msl
    name = File.basename(msl, ".msl").slice(0..99)
    id_name = name.gsub(/[:?!'"%]/,'').gsub(/\s/,'_')
    id = "Custom.attacks.#{id_name}"
    data = {
      name: name,
      category: "Attacks",
      description: "Uploaded from: #{msl}",
      id: id,
#      tags: ['Sanity'],
      metadata: {
        name: "Attacks",
        meta_properties: {
        }
      }
    }
    existing = RestClient.get "#{@studio}/scenarios/#{id}" rescue nil
    action = existing ? "update" : "create"
    RestClient.post "#{@studio}/scenarios/#{action}", {data: data.to_json, file: File.new(msl) }
  end
end

task :initialize do
  begin
    @service = ScenarioService.new ENV['server']
  rescue Exception => e
    puts "#{e.inspect} \nStudio Server must be provided: 'server=<host>'"
  end
end

task :get_scenarios =>[:initialize] do
  @scenarios = @service.get_scenarios "per_page=3000"
  puts "Scenarios found: #{@scenarios.size}"
end

task :create_pcaps do
  @scenarios.each do |scenario|
    id = scenario['_id']
    puts id
    name = scenario['name']
    pcap = @service.offline_pcap id rescue nil
    if pcap
      File.open("pcaps/#{id}.pcap","w+"){|f| f.write pcap}
    end
    print pcap.nil? ? 'X' : '.'
  end
end

desc "download pcap for every scenario in the library"
task :download_all_pcaps => [:get_scenarios, :create_pcaps] do
  puts "Done!"
end

desc "create pcap for each scenario id in an input file: 'scenarios=<filename>'"
task :pcap_from_scenario_ids_file => [:initialize] do
  @scenarios = []
  File.read(ENV['scenarios']).split("\n").each {|s| @scenarios << {'_id' => s}}
  Rake::Task[:create_pcaps].invoke
end

desc "create msl for each pcap in directory: 'dir=<path>'"
task :create_scenarios => [:initialize] do
  dir = ENV['dir']
  Dir.glob("#{dir}/*.{pcap,cap}").each do |pcap|
    msl = @service.create_scenario pcap rescue nil
    name = File.basename pcap, ".*"
    if msl
      File.open("#{dir}/#{name}.msl",'w+'){|f| f.write msl}
    end
    print msl ? '.' : 'x'
  end
end

desc "upload scenario to studio: 'msl=<filename>'"
task :upload_msl => [:initialize] do
  puts @service.upload ENV['msl']
end

desc "upload all msl files in dir to studio: 'dir=<msl dir>'"
task :upload_all => [:initialize] do
  dir = ENV['dir']
  Dir.glob("#{dir}/*.msl") do |msl|
    puts @service.upload msl
  end
end

desc "create msl from each pcap in <dir> and upload to studio: 'dir=<pcap dir>'"
task :create_and_upload_pcap_dir => [:initialize, :create_scenarios, :upload_all]