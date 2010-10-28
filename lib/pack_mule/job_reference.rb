module PackMule
  # This class is a way to pass a reference to another job.
  # It gets stored as a return value for deferred tasks so that
  # we know where to go for the return value.
  class JobReference
    attr_accessor :job
    def initialize(job)
      self.job = job
    end
    alias dereference job
    def rrepr
      "#{self.class.rrepr}.new(#{job.rrepr})"
    end
  end
end
