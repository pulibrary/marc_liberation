# Class for building instances of URI::HTTPS for Orangelight URL's
class OrangelightUrlBuilder
  # Constructor
  # @param ark_cache [CompositeCacheMap] composite of caches for mapping ARK's to BibID's
  # @param service_host [String] the host name for the Orangelight instance
  # @todo Resolve the service_host default parameter properly (please @see https://github.com/pulibrary/marc_liberation/issues/313)
  def initialize(ark_cache:, service_host: 'pulsearch.princeton.edu')
    @ark_cache = ark_cache
    @service_host = service_host
  end

  # Generates an Orangelight URL using an ARK
  # @param ark [URI::ARK] the archival resource key
  # @return URI::HTTPS the URL
  def build(url:)
    if url.is_a? URI::ARK
      cached_bib_id = @ark_cache.fetch("ark:/#{url.naan}/#{url.name}")
    else
      cached_bib_id = @ark_cache.fetch(url.to_s)
    end
    return if cached_bib_id.nil?

    URI::HTTPS.build(host: @service_host, path: "/catalog/#{cached_bib_id}")
  end
end
