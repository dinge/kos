module Kos
end

Dir['%s/*/*.rb' %  File.expand_path("app/kos/")].each do |file|
  require file
end