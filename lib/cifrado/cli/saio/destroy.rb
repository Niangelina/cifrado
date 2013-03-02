module Cifrado
  class Saio < Thor

    desc 'destroy', 'Destroy bootstrapped server'
    option :server_name,  :type => :string, :default => 'cifrado-saio'
    def destroy
      s = service.servers.find {|s| s.name == options[:server_name] }
      if s
        Log.info "Destroying server #{options[:server_name]}."
        s.destroy 
      end
    end

  end
end

