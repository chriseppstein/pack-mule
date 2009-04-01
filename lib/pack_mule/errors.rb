module PackMule
  # raised if we can't create a remote representation of an object using obj.rrepr
  class NoRemoteRepresentationError < StandardError
  end

  # raised if you try to access a result and the task hasn't completed yet.
  class ResultPending < StandardError
  end

  # raised if a job has completed but there's no return value stored for it.
  class ResultMissing < StandardError
  end
end
