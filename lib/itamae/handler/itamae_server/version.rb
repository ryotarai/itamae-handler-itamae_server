module Itamae
  module Handler
    class ItamaeServer < Base
      VERSION = File.read(File.join(__dir__, "version.txt")).strip
    end
  end
end
