require 'elock-client'

conf_file=File.join(File.dirname(__FILE__), "../elock.yml")
elock_config = YAML.load_file(conf_file) if File.exist? conf_file
ELOCK_SERVERS=elock_config ? elock_config['servers'] : []

if ELOCK_SERVERS.empty? || RAILS_ENV == "test"
  RAILS_DEFAULT_LOGGER.info "Using null lock."
  # If there are no servers or we're testing, locking is always successful.
  class NullLock
    def with_lock(name, timeout=nil)
      yield
    end
  end
  LOCK_SERVICE=NullLock.new
else
  # This lock factory manages the connection to elock
  # and the call to with_lock
  class LockFactory
    def self.connection
      @connection ||= begin
        ObjectSpace.define_finalizer(self) do
          self.close_connection
        end
        ELock.new ELOCK_SERVERS.first
      end
    end

    def self.close_connection
      @connection.close
      @connection = nil
    end

    def with_lock(name, timeout=nil, &block)
      LockFactory.connection.with_lock(name, timeout, &block)
    end
  end
  LOCK_SERVICE=LockFactory.new
end
