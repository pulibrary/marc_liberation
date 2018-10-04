require 'json'
require 'faraday'
require 'zlib'
require 'rsolr'
require 'time'

module IndexFunctions

  def self.update_records(dump)
    file_paths = []

    return file_paths unless dump.key? 'files'
    dump_files = dump['files']
    return file_paths unless dump_files.key? 'updated_records'
    updated_records = dump_files['updated_records']

    begin
      updated_records_file_response = Faraday.get(updated_records['dump_file'])
    rescue Faraday::ClientError => client_error
      Rails.logger.error "Failed to retrieve the updated records dump file at: #{updated_records['dump_file']}: #{client_error}"
      return file_paths
    end
    updated_records_file = updated_records_file_response.body

    # updates
    updated_records.each_with_index do |_update, i|
      File.binwrite("/tmp/update_#{i}.gz", updated_records_file)
      file_paths << "/tmp/update_#{i}"
    end

    return file_paths unless dump_files.key? 'new_records'
    new_records = dump_files['new_records']

    begin
      new_records_file_response = Faraday.get(new_records['dump_file'])
    rescue Faraday::ClientError => client_error
      Rails.logger.error "Failed to retrieve the new records dump file at: #{new_records['dump_file']}: #{client_error}"
      return file_paths
    end
    new_records_file = new_records_file_response.body

    # new records
    new_records.each_with_index do |_new_records, i|
      File.binwrite("/tmp/new_#{i}.gz", new_records_file)
      file_paths << "/tmp/new_#{i}"
    end

    file_paths
  end

  def self.delete_ids(dump)
    dump['ids']['delete_ids'].map { |h| h['id'] }
  end

  def self.rsolr_connection(solr_url)
    RSolr.connect(url: solr_url, read_timeout: 300, open_timeout: 300)
  end

  def self.full_dump(event)
    file_paths = []
    dump = JSON.parse(Faraday.get(event['dump_url']).body)
    dump['files']['bib_records'].each_with_index do |bib, i|
      File.binwrite("/tmp/bib_#{i}.gz", Faraday.get(bib['dump_file']).body)
      file_paths << "/tmp/bib_#{i}"
    end
    file_paths
  end


  def self.unzip(marc_dump)
    Zlib::GzipReader.open("#{marc_dump}.gz") do |gz|
      File.open("#{marc_dump}.xml", 'wb') do |fp|
        while chunk = gz.read(16 * 1024) do
          fp.write chunk
        end
      end
      gz.close
    end
  end
end
