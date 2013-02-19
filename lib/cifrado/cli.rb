module Cifrado
  class CLI < Thor

    include Cifrado
    include Cifrado::Utils

    attr_reader :config

    check_unknown_options!

    class_option :username
    class_option :quiet
    class_option :password
    class_option :auth_url
    class_option :insecure, :type => :boolean, :desc => "Insecure SSL connections"

    desc "stat [CONTAINER] [OBJECT]", "Displays information for the account, container, or object."
    def stat(container = nil, object = nil)
      client = client_instance
      creds = client.service.credentials

      uri = URI.parse creds[:server_management_url]
      url = "#{uri.to_s}/#{[container, object].compact.join("/")}"
      Log.debug "HEAD #{url}"

      r = client.head url
      path = ''
      path << container if container
      path = File.join(container, object) if object
      
      # Look for the hashed object in case it was encrypted
      if r.status == 404 and object
        file_hash = Digest::SHA2.new << object
        url = "#{uri.to_s}/#{path}"
        Log.debug "HEAD #{url}"
        r = client.head "#{url}"
      end

      if r.status == 404
        if object
          Log.error 'Object not found'
        else
          Log.error 'Container not found'
        end
      else
        puts "Account:".ljust(30) + File.basename(uri.path)
        r.headers.sort.each do |k, v| 
          if k == 'X-Timestamp'
            puts "#{(k + ":").ljust(30)}#{v} (#{unix_time(v)})" 
          elsif k == 'X-Account-Bytes-Used' or k == 'Content-Length'
            puts "#{(k + ":").ljust(30)}#{v} (#{humanize_bytes(v)})" 
          elsif k == 'X-Object-Meta-Encrypted-Name'
            puts "#{(k + ":").ljust(30)}#{v}"
          else
            puts "#{(k + ":").ljust(30)}#{v}" 
          end
        end
        r.headers
      end
    end

    desc "download [CONTAINER] [OBJECT]", "Download container, objects"
    option :decrypt, :type => :boolean
    option :output
    def download(container, object = nil)
      client = client_instance
      if object
        Log.info "Downloading #{object}..."
      else
        Log.info "Downloading container files from #{container}"
      end
      r = client.download container, object, 
                          :decrypt => options[:decrypt],
                          :output => options[:output]
      found = (r.status != 404)
      if !found and object
        Log.debug 'Trying to find hashed object name'
        file_hash = (Digest::SHA2.new << object).to_s
        r = client.download container, file_hash,
                            :decrypt => options[:decrypt],
                            :output => options[:output]
        found = true if r.status == 200
      end
      unless found
        Log.error "File #{object} not found in #{container}"
        exit 1
      end
    end

    # @returns [Array] a list of Fog::OpenStack::File or
    # Fog::OpenStack::Directory
    #
    desc "list [CONTAINER]", "List containers and objects"
    option :list_segments, :type => :boolean
    option :fast, :type => :boolean
    option :display_hash, :type => :boolean
    def list(container = nil)
      client = client_instance
      if container
        dir = client.service.directories.get container
        if dir
          Log.info "Listing objects in '#{container}'"
          files = dir.files
          files.each do |f|
            if options[:fast]
              puts f.key
              next
            end
            # Skip segments
            next if f.key =~ /\/segments\/\d+\.\d{2}\/\d+\/\d+/ and \
                    not options[:list_segments]

            metadata = f.metadata
            if metadata[:encrypted_name] 
              fname = decrypt_filename metadata[:encrypted_name], @config[:password]
              puts "#{fname.ljust(55)} #{set_color("[encrypted]",:red, :bold)}"
              puts "  hash: #{f.key}" if options[:display_hash]
            else
              puts f.key.ljust(55)
            end
          end 
          files
        else
          Log.error "Container '#{container}' not found"
        end
      else
        Log.info "Listing containers"
        directories = client.service.directories
        directories.each { |d| puts d.key }
        directories
      end
    end

    desc "container-add CONTAINER [DESCRIPTION]", "Create a container"
    def container_add(container, description = '')
      client = client_instance
      client.service.directories.create :key => container, 
                                        :description => description
    end

    desc "delete CONTAINER [OBJECT]", "Delete specific container or object"
    def delete(container, object = nil)
      client = client_instance
      begin
        if object
          Log.info "Deleting file #{object}..."
          deleted = false
          begin
            client.service.delete_object container, object
            deleted = true
          rescue Fog::Storage::OpenStack::NotFound
            Log.debug 'Trying to find hashed object name'
            file_hash = (Digest::SHA2.new << object).to_s
            deleted = client.service.delete_object(container, file_hash) rescue nil
          end
          if deleted
            Log.info "File #{object} deleted"
          else
            Log.error "File #{object} not found"
          end
        else
          Log.info "Deleting container #{container}..."
          dir = client.service.directories.get(container)
          if dir
            dir.files.each do |f|
              Log.debug "Deleting file #{f.key}..."
              f.destroy
            end
            dir.destroy
            Log.info "Container #{container} deleted"
          end
        end
      rescue => e
        Log.error e.message
        Log.debug e.backtrace
      end
    end

    desc "cache-clean", "Empty Cifrado's cache directory"
    def cache_clean
      Log.info "Cleaning cache dir #{Config.instance.cache_dir}"
      Dir["#{Config.instance.cache_dir}/*"].each { |f| File.delete f }
    end

    desc "setup", "Initial Cifrado configuration"
    def setup
      check_options options
      Log.debug "Setup done"
    end

    desc "set-acl CONTAINER", 'Set an ACL on containers and objects'
    option :acl, :type => :string, :required => true
    def set_acl(container, object = nil)
      client = client_instance
      client.set_acl options[:acl], container
    end

    desc "upload CONTAINER FILE", "Upload a file"
    option :encrypt, :desc => 'Encrypt: a:recipient (asymmetric) or symmetric'
    option :segments, :type => :numeric, :desc => "Split the data in segments"
    option :strip_path, :type => :boolean
    option :progressbar, :default => :fancy
    def upload(container, file)
      unless File.exist?(file)
        Log.error "File '#{file}' does not exist"
        exit 1
      end

      client = client_instance 

      tstart = Time.now
      uploaded = nil
      begin
        if options[:segments]
          uploaded = split_and_upload client, container, file
        else
          uploaded = upload_single client, container, file
        end
        tend = Time.now
        Log.info "Time taken #{(tend - tstart).round} s."
        uploaded
      rescue Exception => e
        Log.error e.message
        Log.debug e.backtrace.inspect
        exit 1
      end
    end

    private
    def client_instance

      if options[:quiet] and Log.level < Logger::WARN
        Log.level = Logger::WARN
      end

      begin
        config = check_options
        if options[:insecure]
          Log.warn "SSL verification DISABLED"
        end
        client = Cifrado::SwiftClient.new :username => config[:username], 
                                          :api_key  => config[:password],
                                          :auth_url => config[:auth_url],
                                          :connection_options => { 
                                            :ssl_verify_peer => !options[:insecure] 
                                          }
        @client = client
        @config = config
        return client
      rescue Excon::Errors::Unauthorized => e
        Log.error set_color("Unauthorized.", :red, true)
        Log.error "Double check the username, password and auth_url."
      rescue Excon::Errors::SocketError => e
        if e.message =~ /Unable to verify certificate|hostname does not match the server/
          Log.error "Unable to verify SSL certificate."
          Log.error "If the server is using a self-signed certificate, try using --insecure."
          Log.error "Please be aware of the security implications."
        else
          Log.error e.message
        end
        Log.debug e.backtrace.inspect
      rescue Exception => e
        Log.error e.message
        Log.debug e.backtrace.inspect
      ensure
        system 'stty echo icanon'
      end
      exit 1
    end

    def check_options
      config_file = File.join(ENV['HOME'], '.cifradorc')
      config = {}

      if File.exist?(config_file)
        begin
          Log.debug "Configuration file found: #{config_file}"
          Cifrado::Log.debug "Trying to read config file #{config_file}"
          config = YAML.load_file(config_file)
          Cifrado::Log.debug "Config #{config_file} read"
          original_config = config.dup
        rescue => e
          Cifrado::Log.error "Error loading config file"
          Cifrado::Log.error e.message
        end
      end

      config[:username] = options[:username] || config[:username] || ask('username:')
      if options[:password] or config[:password]
        config[:password] = options[:password] || config[:password]
      else
        system 'stty -echo -icanon'
        config[:password] = ask('password:')
        system 'stty echo icanon'
        puts
      end
      config[:auth_url] = options[:auth_url] || config[:auth_url] || ask('auth_url:')

      unless File.exist?(config_file)
        puts
        puts "Cifrado can save this settings in #{ENV['HOME']}/.cifradorc"
        puts "for later use."
        puts "The settings (password included) are saved unencrypted."
        puts
        if yes? "Do you want to save these settings?"
          File.open(config_file, 'w') do |f| 
            f.puts config.to_yaml
            f.chmod 0600
          end
          @settings_saved = true
        end
      end

      if original_config != config and !@settings_saved
        puts "username, password and/or auth_url changed"
        if yes? "Do you want to save the NEW settings?"
          File.open(config_file, 'w') { |f| f.puts config.to_yaml }
        end
      end

      config
    end

    def upload_single(client, container, object)
      fsize = File.size(object)
      fbasename = File.basename(object)
      Log.info "Uploading #{fbasename} (#{humanize_bytes(fsize)})"

      pb = Progressbar.new 1, 1, :style => options[:progressbar]

      config = Cifrado::Config.instance
      object_path = object
      object_path = File.basename(object) if options[:strip_path]
      if cs = needs_encryption
        encrypted_file = File.join(config.cache_dir, File.basename(object))
        Log.debug "Writing encrypted file to #{encrypted_file}"
        encrypted_output = cs.encrypt object, 
                                      encrypted_file
        encrypted_name = encrypt_filename object, @config[:password]
        client.upload container, 
                      encrypted_output, 
                      :headers => { 
                        'X-Object-Meta-Encrypted-Name' => encrypted_name
                      },
                      :object_path => File.basename(encrypted_output),
                      :progress_callback => pb.block
        object_path = File.basename(encrypted_output)
        File.delete encrypted_output 
      else
        client.upload container, 
                      object,
                      :object_path => object_path,
                      :progress_callback => pb.block
      end
      object_path
    end

    def needs_encryption
      return nil unless options[:encrypt]

      tokens = options[:encrypt].split(':')
      etype = tokens.first
      if etype == 'a'
        recipient = tokens[1..-1].join(':')
        CryptoServices.new :type => :asymmetric, 
                                    :recipient => recipient, 
                                    :encrypt_name => true
      elsif etype == 's' or etype == 'symmetric'
        if etype == 'symmetric'
          Log.info "Password to encrypt the data required"
          system 'stty -echo -icanon'
          passphrase = ask("Enter passphrase:")
          puts
          passphrase2 = ask("Repeat passphrase:")
          puts
          if passphrase != passphrase2
            raise 'Passphrase does not match'
          end
          system 'stty echo icanon'
        else
          passphrase = tokens[1..-1].join(':')
        end
        unless passphrase
          raise "Invalid symmetric encryption passprase"
        end
        CryptoServices.new :type => :symmetric, 
                                    :passphrase => passphrase, 
                                    :encrypt_name => true
      else
        raise "Invalid encryption type #{etype}."
      end
    end

    def encrypt_if_required(file)
      if cs = needs_encryption
        Log.debug "Encrypting object #{file}"
        cache_dir = Cifrado::Config.instance.cache_dir
        encrypted_output = cs.encrypt file, 
                                      File.join(cache_dir, File.basename(file))
      else
        file
      end
    end

    # FIXME: needs refactoring
    def split_and_upload(client, container, object)
      fbasename = File.basename(object)

      # Encrypts the file if required
      out = encrypt_if_required(object)

      splitter = FileSplitter.new out, options[:segments]

      if options[:encrypt]
        target_manifest = File.basename(out)
      else
        target_manifest = (options[:strip_path] ? \
                              File.basename(object) : object.gsub(/^\//, ''))
      end

      Log.info "Segmenting file, #{options[:segments]} segments..."
      Log.info "Uploading #{fbasename} segments"

      segments_uploaded = []
      splitter.split do |n, segment|
        segment_size = File.size segment
        hsegment_size = humanize_bytes segment_size
        Log.info "Uploading segment #{n}/#{options[:segments]} (#{hsegment_size})"

        segment_number = "%08d" % n
        if options[:encrypt]
          suffix = splitter.chunk_suffix + segment_number
          obj_path = File.basename(out) + suffix
          Log.debug "Encrypted object path: #{obj_path}"
          encrypted_name = encrypt_filename object + suffix,
                                            @config[:password]
          headers = { 
            'X-Object-Meta-Encrypted-Name' => encrypted_name 
          }
        else
          obj_path = object + splitter.chunk_suffix + segment_number
          Log.debug "Unencrypted object path #{obj_path}"
          if options[:strip_path]
            obj_path = File.basename(obj_path) 
            Log.debug "Stripping path from object: #{obj_path}"
          end
          Log.debug "Uploading segment #{obj_path} (#{segment_size} bytes)..."
          headers = {}
        end

        pb = Progressbar.new options[:segments],
                             n,
                             :style => options[:progressbar]

        client.upload container, 
                      segment,
                      :headers => headers,
                      :object_path => obj_path,
                      :progress_callback => pb.block

        File.delete segment
        segments_uploaded << obj_path
      end
      
      # We need this for segmented uploads
      Log.debug "Adding manifest #{target_manifest}"
      headers = {}
      if options[:encrypt]
        encrypted_name = encrypt_filename object, @config[:password]
        headers = { 'X-Object-Meta-Encrypted-Name' => encrypted_name }
      end
      client.service.put_object_manifest container, 
                                         target_manifest,
                                         headers  
      segments_uploaded.insert 0, target_manifest

      # Delete temporal encrypted file created by GPG
      if options[:encrypt]
        Log.debug "Deleting temporal encrypted file #{out}"
        File.delete out 
      end
      segments_uploaded
    end

  end
end
