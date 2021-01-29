require 'rubygems/package'
class Alma::Indexer
  include Rails.application.routes.url_helpers
  attr_reader :solr_url
  def initialize(solr_url:)
    @solr_url = solr_url
  end

  def full_reindex!
    full_reindex_file_urls.each do |url|
      download_and_decompress(url) do |file|
        index_file(file.path)
      end
    end
  end

  def index_file(file_name)
    `traject -c marc_to_solr/lib/traject_config.rb #{file_name} -u #{solr_url}; true`
  end

  def default_url_options
    Rails.configuration.action_mailer.default_url_options
  end

  private

    def download_and_decompress(url)
      Tempfile.create(downloaded_filename(url), binmode: true) do |downloaded_tmp|
        tar_reader(url, downloaded_tmp).each.map do |entry|
          Tempfile.create(decompressed_filename(entry), binmode: true) do |decompressed_tmp|
            decompressed_file = decompress(entry, decompressed_tmp)
            entry.close
            yield(decompressed_file)
          end
        end
      end
    end

    def tar_reader(url, temp_file)
      temp_file.puts Faraday.get(url).body
      temp_file.rewind
      tar_extract = Gem::Package::TarReader.new(Zlib::GzipReader.open(temp_file.path))
      tar_extract.tap(&:rewind)
    end

    def decompress(entry, temp_file)
      while (chunk = entry.read(16 * 1024))
        temp_file.write chunk
      end
      temp_file.tap(&:rewind)
    end

    def decompressed_filename(entry)
      file_name, decompress_extension = entry.full_name.split(".")
      decompress_extension ||= "xml"
      ["full_reindex_file_unzip_#{file_name}", "." + decompress_extension]
    end

    def downloaded_filename(url)
      extension = "." + url.split("/").last.split(".", 2).last
      ["full_reindex_file", extension]
    end

    def full_reindex_event
      Event.joins(dump: :dump_type).where(success: true, 'dump_types.constant': "ALL_RECORDS").order(finish: 'DESC').first!
    end

    def full_reindex_files
      full_reindex_event.dump.dump_files.joins(:dump_file_type).where('dump_file_types.constant': 'BIB_RECORDS')
    end

    def full_reindex_file_urls
      full_reindex_files.map { |file| dump_file_url(file.id) }
    end
end
