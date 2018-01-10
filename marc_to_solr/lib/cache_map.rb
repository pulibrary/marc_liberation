require 'faraday'

# Cached mapping of ARKs to Bib IDs
# Retrieves and stores paginated Solr responses containing the ARK's and BibID's
class CacheMap

  # Constructor
  # @param cache [ActiveSupport::Cache::Store] Rails low-level cache
  # @param host [String] the host for the Blacklight endpoint
  # @param path [String] the path for the Blacklight endpoint
  # @param rows [Integer] the number of rows for each Solr response
  # @param logger [IO] the logging device
  def initialize(cache:, host:, path: '/catalog.json', rows: 1000000, logger: STDOUT)
    @cache = cache
    @host = host
    @path = path
    @rows = rows
    @logger = logger
    @values = {}

    seed!
  end

  # Seed the cache
  # @param page [Integer] the page number at which to start the caching
  def seed!(page: 1)
    # Attempt to retrieve the values cached from Solr
    cached_values = @cache.fetch(cache_key)
    unless cached_values.nil?
      @values = cached_values
      return
    end

    response = query(page: page)
    return if response.empty?

    pages = response.fetch('pages')

    cache_page(response)

    if pages.fetch('last_page?') == false
      seed!(page: page + 1)
    else
      @cache.write(cache_key, @values)
    end
  end

  # Fetch a BibID from the cache
  # @param ark [String] the ARK mapped to the BibID
  # @return [String, nil] the BibID (or nil if it has not been mapped)
  def fetch(ark)
    @values.fetch(ark, nil)
  end

  private

    # Cache a page
    # @param page [Hash] Solr response page
    def cache_page(page)
      docs = page.fetch('docs')
      docs.each do |doc|
        arks = doc.fetch('identifier_ssim', [])
        bib_ids = doc.fetch('source_metadata_identifier_ssim', [])

        ark = arks.first
        bib_id = bib_ids.first

        @values[ark] = bib_id
      end
    end

    # Query the service using the endpoint
    # @param [Integer] the page parameter for the query
    def query(page: 1)
      begin
        url = URI::HTTPS.build(host: @host, path: @path, query: "q=&rows=#{@rows}&page=#{page}&f[identifier_tesim][]=ark")
        http_response = Faraday.get(url)

        values = JSON.parse(http_response.body)
        values.fetch('response')
      rescue StandardError => err
        @logger.error "Failed to seed the ARK cached from the repository: #{err}"
        {}
      end
    end

    # Generate the unique key for the cache from the hostname and path for Solr
    # @return [String] the cache key
    def cache_key
      [@host.gsub(/[\.\/]/, '_'), @path.gsub(/[\.\/]/, '_')].join('_')
    end
end
