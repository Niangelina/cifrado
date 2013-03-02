require 'cifrado/cli/saio/base'

module Cifrado
  class CLI
    desc "saio SUBCOMMAND ...ARGS", "Bootstrap a Swift installation"
    subcommand "saio", Saio
  end
end

require 'cifrado/cli/saio/bootstrap'
require 'cifrado/cli/saio/destroy'
