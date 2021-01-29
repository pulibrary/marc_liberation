require 'faraday'
require 'json'
require 'lightly'
require 'rsolr'
require 'time'
require 'zlib'

require_relative '../../marc_to_solr/lib/cache_adapter'
require_relative '../../marc_to_solr/lib/cache_manager'
require_relative '../../marc_to_solr/lib/cache_map'
require_relative '../../marc_to_solr/lib/composite_cache_map'

default_bibdata_url = 'https://bibdata.princeton.edu'
bibdata_url = ENV['BIBDATA_URL'] || default_bibdata_url

conn = Faraday.new(url: bibdata_url) do |faraday|
  faraday.request  :url_encoded             # form-encode POST params
  faraday.response :logger                  # log requests to STDOUT
  faraday.adapter  Faraday.default_adapter  # make requests with Net::HTTP
end

default_solr_url = 'http://localhost:8983/solr/blacklight-core-development'
commit = "-s solrj_writer.commit_on_close=true"
binary = "-t binary"

desc "Index MARC against SET_URL, set NO_COMMIT to 1 to skip commit"
task :index do
  if ENV['MARC']
    url_arg = ENV['SET_URL'] ? "-u #{ENV['SET_URL']}" : ''
    fixtures = ENV['MARC']
    if ENV['NO_COMMIT'] && ENV['NO_COMMIT'] == '1'
      sh "traject -c marc_to_solr/lib/traject_config.rb #{fixtures} #{url_arg}"
    else
      sh "traject -c marc_to_solr/lib/traject_config.rb #{fixtures} #{url_arg} #{commit}"
    end
  end
end

desc "Index MARC_PATH files against SET_URL"
task :index_folder do
  solr_url = ENV['SET_URL'] || default_solr_url
  Dir["#{ENV['MARC_PATH']}/*.xml"].sort.each { |fixtures| sh "rake index SET_URL=#{solr_url} MARC=#{fixtures} NO_COMMIT=1; true" }
  solr = IndexFunctions.rsolr_connection(solr_url)
  solr.commit
end

desc "which chunks from BIB_DUMP didn't index against SET_URL?"
task :check do
  if ENV['BIB_DUMP']
    index_url = ENV['SET_URL'] || default_solr_url
    solr = IndexFunctions.rsolr_connection(index_url)
    `awk 'NR % 50000 == 0 {print} END {print}' #{ENV['BIB_DUMP']}`.split("\n").each_with_index do |bib, i|
      puts i if solr.get('get', params: { id: "#{bib}" })["doc"].nil?
    end
  end
end

desc "which of the BIBS given didn't index against SET_URL?"
task :check_given do
  if ENV['BIBS']
    index_url = ENV['SET_URL'] || default_solr_url
    solr = IndexFunctions.rsolr_connection(index_url)
    `awk '{print}' #{ENV['BIBS']}`.split("\n").each do |bib|
      puts bib if solr.get('get', params: { id: "#{bib}" })["doc"].nil?
    end
  end
end

desc "which chunks from BIB_DUMP indexed against SET_URL?"
task :check_included do
  if ENV['BIB_DUMP']
    index_url = ENV['SET_URL'] || default_solr_url
    solr = IndexFunctions.rsolr_connection(index_url)
    `awk 'NR % 50000 == 0 {print} END {print}' #{ENV['BIB_DUMP']}`.split("\n").each_with_index do |bib, i|
      puts i unless solr.get('get', params: { id: "#{bib}" })["doc"].nil?
    end
  end
end

desc "Deletes given BIB from SET_URL"
task :delete_bib do
  solr_url = ENV['SET_URL'] || default_solr_url
  solr = IndexFunctions.rsolr_connection(solr_url)
  if ENV['BIB']
    solr.delete_by_id(ENV['BIB'])
    solr.commit
  else
    puts 'Please provide a BIB argument (BIB=####)'
  end
end

namespace :liberate do
  desc "Index VoyRec for given BIB, against SET_URL"
  task :bib do
    url_arg = ENV['SET_URL'] ? "-u #{ENV['SET_URL']}" : ''
    if ENV['BIB']
      resp = conn.get "/bibliographic/#{ENV['BIB']}"
      File.binwrite('./tmp/tmp.xml', resp.body)
      sh "traject -c marc_to_solr/lib/traject_config.rb ./tmp/tmp.xml #{url_arg} #{commit}"
    else
      puts 'Please provide a BIB argument (BIB=####)'
    end
  end

  desc "Index VoyRec with all changed records since SET_DATE, against SET_URL"
  task :updates do
    solr_url = ENV['SET_URL'] || default_solr_url
    solr = IndexFunctions.rsolr_connection(solr_url)
    resp = conn.get '/events.json'
    comp_date = ENV['SET_DATE'] ? Date.parse(ENV['SET_DATE']) : (Date.today - 1)
    all_events = JSON.parse(resp.body).select { |e| Date.parse(e['start']) >= comp_date && e['success'] && e['dump_type'] == 'CHANGED_RECORDS' }.each do |event|
      dump = JSON.parse(Faraday.get(event['dump_url']).body)
      IndexFunctions.update_records(dump).each do |marc|
        IndexFunctions.unzip_mrc(marc)
        sh "traject -c marc_to_solr/lib/traject_config.rb #{marc}.mrc -u #{solr_url} #{binary}; true"
        File.delete("#{marc}.mrc")
        File.delete("#{marc}.gz")
      end
      solr.delete_by_id(IndexFunctions.delete_ids(dump))
    end
    solr.commit
  end

  desc "Index VoyRec updates on SET_DATE against SET_URL"
  task :on do
    solr_url = ENV['SET_URL'] || default_solr_url
    solr = IndexFunctions.rsolr_connection(solr_url)
    resp = conn.get '/events.json'
    if event = JSON.parse(resp.body).detect { |e| Date.parse(e['start']) == Date.parse(ENV['SET_DATE']) && e['success'] && e['dump_type'] == 'CHANGED_RECORDS' }
      dump = JSON.parse(Faraday.get(event['dump_url']).body)
      IndexFunctions.update_records(dump).each do |marc|
        IndexFunctions.unzip_mrc(marc)
        sh "traject -c marc_to_solr/lib/traject_config.rb #{marc}.mrc -u #{solr_url} #{binary}; true"
        File.delete("#{marc}.mrc")
        File.delete("#{marc}.gz")
      end
      solr.delete_by_id(IndexFunctions.delete_ids(dump))
    end
    solr.commit
  end

  desc "Index VoyRec with today's changed records, against SET_URL"
  task :latest do
    solr_url = ENV['SET_URL'] || default_solr_url
    solr = IndexFunctions.rsolr_connection(solr_url)
    resp = conn.get '/events.json'
    event = JSON.parse(resp.body).last
    if event['success'] && event['dump_type'] == 'CHANGED_RECORDS'
      dump = JSON.parse(Faraday.get(event['dump_url']).body)
      IndexFunctions.update_records(dump).each do |marc|
        IndexFunctions.unzip_mrc(marc)
        sh "traject -c marc_to_solr/lib/traject_config.rb #{marc}.mrc -u #{solr_url} #{binary}; true"
        File.delete("#{marc}.mrc")
        File.delete("#{marc}.gz")
      end
      solr.delete_by_id(IndexFunctions.delete_ids(dump))
    end
    solr.commit
  end

  desc "Index latest full record dump against SET_URL"
  task full: :environment do
    solr_url = ENV['SET_URL'] || default_solr_url
    solr = IndexFunctions.rsolr_connection(solr_url)
    Alma::Indexer.new(solr_url: solr_url).full_reindex!
    solr.commit
  end

  desc "Index a single MARC XML file against SET_URL"
  task index_file: :environment do
    solr_url = ENV['SET_URL'] || default_solr_url
    file_name = ENV['FILE']
    abort "MARC XML file name must be indicated" unless file_name
    solr = IndexFunctions.rsolr_connection(solr_url)
    Alma::Indexer.new(solr_url: solr_url).index_file(file_name)
    solr.commit
  end

  namespace :arks do
    desc "Seed the ARK cache"
    task :seed_cache, [:figgy_dir_path] do |_t, args|
      figgy_dir_path = args[:figgy_dir_path] || Rails.root.join('tmp', 'figgy_ark_cache')
      figgy_lightly = Lightly.new(dir: figgy_dir_path, life: 0, hash: false)
      figgy_cache_adapter = CacheAdapter.new(service: figgy_lightly)

      logger = Logger.new(STDOUT)
      cache_manager = CacheManager.initialize(figgy_cache: figgy_cache_adapter, logger: logger)
      cache_manager.seed!
    end

    desc "Clear the ARK cache"
    task :clear_cache, [:figgy_dir_path] do |_t, args|
      figgy_dir_path = args[:figgy_dir_path] || Rails.root.join('tmp', 'figgy_ark_cache')
      CacheManager.clear(dir: figgy_dir_path)
    end

    desc "Clear, then seed, the ARK cache"
    task :clear_and_seed_cache, [:figgy_dir_path] do |_t, args|
      figgy_dir_path = args[:figgy_dir_path] || Rails.root.join('tmp', 'figgy_ark_cache')
      Rake::Task["liberate:arks:clear_cache"].invoke(figgy_dir_path)
      Rake::Task["liberate:arks:seed_cache"].invoke(figgy_dir_path)
    end
  end
end
