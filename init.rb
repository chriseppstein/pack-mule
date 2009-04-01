require File.join(File.dirname(__FILE__), 'lib', 'pack_mule')
require File.join(File.dirname(__FILE__), 'lib', 'pack_mule', 'async_observer_extensions')

AsyncObserver::Worker.send(:include, PackMule::AsyncOberserverExtensions)
