module PackMule
  # This class is a way to pass a reference to another job.
  # It gets stored as a return value for deferred tasks so that
  # we know where to go for the return value.
  class JobReference
    attr_accessor :id, :server
    def initialize(id, server)
      self.id = id
      self.server = server
    end
    def to_a
      [id, server]
    end
    alias dereference to_a
    def rrepr
      "#{self.class.rrepr}.new(#{id.rrepr}, #{server.rrepr})"
    end
  end
end
