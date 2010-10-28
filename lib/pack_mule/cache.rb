module PackMule
  # An abstract class representing a cache where
  # progress tracking and return values can be kept
  # during a run
  class CacheStore
    def get(key)
      raise "Not Implemented"
    end
    def [](key)
      get(key)
    end

    def set(key, value)
      raise "Not Implemented"
    end
    def []=(key, value)
      set(key, value)
    end

    def rrepr
      raise "Not Implemented"
    end
  end

  class RailsDefaultCacheStore < CacheStore

    def get(key)
      CACHE[key]
    end

    def set(key, value)
      CACHE[key] = value
    end

    def rrepr
      "#{self.class.name}.new"
    end
  end

end
