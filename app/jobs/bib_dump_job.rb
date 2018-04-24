require 'voyager_helpers'

class BibDumpJob < ActiveJob::Base
  queue_as :default

  # Dump Marc XML to disk, index to solr, and zip
  # Option to post to a separate url for reindex
  def perform(id_slice, df_id, reindex=false)
    df = DumpFile.find(df_id)
    File.truncate(df.path, 0) if File.exist?(df.path)
    VoyagerHelpers::Liberator.dump_bibs_to_file(id_slice, df.path)
    index(df.path, reindex)
    df.zip
    df.save
  end

  def index(path, reindex)
    process_locations unless Rails.env.test? || !ActiveRecord::Base.connection.table_exists?('locations_holding_locations')
    indexer = Traject::Indexer.new
    indexer.load_config_file(Rails.application.config.traject['config'])
    indexer.settings['solr.url'] = ENV['SOLR_REINDEX_URL'] if reindex
    indexer.process(path)
  end
end
