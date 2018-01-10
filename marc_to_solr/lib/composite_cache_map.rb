# Composite of CacheMaps
# Provides the ability to build a cache from multiple Solr endpoints
class CompositeCacheMap
  # Constructor
  # @param cache_maps [Array<CacheMap>] the CacheMap instances for each endpoint
  def initialize(cache_maps:)
    @cache_maps = cache_maps
  end

  # Seed the cache
  # @param page [Integer] the page number at which to start the caching
  def seed!(page: 1)
    @cache_maps.each { |cache_map| cache_map.seed!(page: page) }
  end

  # Retrieve the cached values
  # @return [Hash] the values cached from the Solr response
  def values
    @values ||= @cache_maps.map { |cache_map| cache_map.values }.reduce(&:merge)
  end

  # Fetch the first BibID mapped to an ARK from the cache
  # @param ark [String] the ARK mapped to the BibID
  # @return [String, nil] the BibID (or nil if it has not been mapped)
  def fetch(ark)
    bib_ids = @cache_maps.map { |cache_map| cache_map.fetch(ark) }
    bib_ids.first
  end
end
