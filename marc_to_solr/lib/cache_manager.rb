# Class for handling instances of caching objects
class CacheManager
  # Build and set the current cache to the new instance
  # @param cache [ActiveSupport::Cache::Store] Rails low-level cache
  # @param logger [IO] logger for handling output during HTTP service requests
  def self.initialize(cache:, logger: STDOUT)
    @current_cache = new(cache: cache, logger: logger)
  end

  # Retrieve the last initialized cache manager
  # Raises an error if a cache hasn't been initialized
  # @return [CacheManager]
  def self.current
    @current_cache
    rescue
      raise NotImplementedError, 'Please initialize a cache using CacheManager.initialize(cache: Rails.cache, logger: Rails.logger)'
  end

  # Constructor
  # @param cache [ActiveSupport::Cache::Store] Rails low-level cache
  # @param logger [IO] logger for handling output during HTTP service requests
  def initialize(cache:, logger: STDOUT)
    @cache = cache
    @logger = logger

    # Seed the caches
    seed!
  end

  # Retrieve the stored (or seed) the cache for the ARK's in Figgy
  # @return [CacheMap]
  def figgy_ark_cache
    @figgy_ark_cache ||= CacheMap.new(cache: @cache, host: "figgy.princeton.edu", logger: @logger)
  end

  # Retrieve the stored (or seed) the cache for the ARK's in Plum
  # @return [CacheMap]
  def plum_ark_cache
    @figgy_ark_cache ||= CacheMap.new(cache: @cache, host: "plum.princeton.edu", logger: @logger)
  end

  # Retrieve the stored (or seed) the cache for the ARK's in all repositories
  # @return [CompositeCacheMap]
  def ark_cache
    @cache_maps ||= CompositeCacheMap.new(cache_maps: [figgy_ark_cache, plum_ark_cache])
  end

  private

    # Ensure the the CacheMap and CompositeCacheMap instances are memoized
    def seed!
      figgy_ark_cache
      plum_ark_cache
      ark_cache
    end
end
