module PackMule
  class NoRemoteRepresentationError < StandardError
  end

  class ResultPending < StandardError
  end

  class ResultMissing < StandardError
  end
end
