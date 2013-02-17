require 'digest/sha2'
require 'base64'

module Cifrado
  class CryptoServices

    def initialize(options = {})
      require 'shellwords'
      require 'securerandom'
      @options = options
      @gpg_binary = @options[:gpg_binary] || '/usr/bin/gpg'
      @gpg_extra_args = @options[:gpg_extra_args] || []
      @gpg_extra_args = @gpg_extra_args.concat %w(--batch --yes)
      @encrypt_name = @options[:encrypt_name] || false
    end

    def encrypt(file, output)
      unless file and File.exist?(file)
        raise ArgumentError.new "Invalid file #{file}"
      end

      if output.nil?
        raise ArgumentError.new "Invalid output file path"
      end

      # so we can use --use-embedded-filename to recover the original
      # filename
      Log.debug "Setting GPG filename #{file} (Base64 URL encoded)"
      @gpg_extra_args << "--set-filename '#{Base64.urlsafe_encode64(file)}'"

      check_args
      raise ArgumentError.new("#{@gpg_binary} not found") unless File.exist?(@gpg_binary)

      Log.debug "Encrypting file #{file}..."
      if @encrypt_name and output != '-'
        Log.debug "Scrambling file name #{file}..."
        dir = File.dirname(output)
        #output = File.join dir, (Digest::SHA2.new << (output + SecureRandom.hex)).to_s
        output = File.join dir, (Digest::SHA2.new << file).to_s
      end
      
      if output != '-'
        @gpg_extra_args << ["--output #{Shellwords.escape(output)}"]
      end

      if @options[:type] == :asymmetric 
        asymmetric file, output
      else @options[:type] == :symmetric
        symmetric file, output
      end
    end

    def self.encrypted?(file)
      output = `/usr/bin/gpg --yes --batch --no-use-agent --list-packets #{file} 2>&1`
      Log.debug output
      if output.match(/AES256 encrypted|encrypted with\s.*\skey,\sID\s.*created/m).nil?
        return false
      end
      true
    end

    def decrypt(file, output)
      unless file and File.exist?(file)
        raise ArgumentError.new "Invalid file #{file}"
      end

      if output.nil?
        raise ArgumentError.new "Invalid output file path"
      end

      raise ArgumentError.new("#{@gpg_binary} not found") unless File.exist?(@gpg_binary)

      Log.debug "Decrypting file #{file}..."
      
      if output != '-'
        @gpg_extra_args << ["--output #{Shellwords.escape(output)}"]
      end
      
      cmd = "#{@gpg_binary} #{@gpg_extra_args.join(' ')} --decrypt #{Shellwords.escape(file)}"
      Log.debug "Decrypting with: #{cmd}"
      out = `#{cmd} 2>&1`
      
      if $? != 0
        raise "Failed to decrypt file #{file}\n#{out}"
      else
        if @options[:delete_source]
          File.delete file 
          Log.debug "Deleting encrypted file #{file}"
        end
      end

      Log.debug out
      output
    end

    private

    def check_args
      if @options[:type] == :asymmetric 
        unless @options[:recipient]
          raise ArgumentError.new('Missing encryption recipient')
        end
      elsif @options[:type] == :symmetric
        unless @options[:passphrase]
          raise ArgumentError.new('Missing encryption passphrase')
        end
      else
        raise ArgumentError.new "Unknown encryption type #{@options[:type]}"
      end
    end

    def symmetric(file, output)
      pfile = "/tmp/#{SecureRandom.hex}"
      File.open(pfile, 'w') { |f| f.puts @options[:passphrase]; f.sync }
      cmd = "#{@gpg_binary} #{@gpg_extra_args.join(' ')} --no-use-agent --passphrase-file #{pfile} --cipher-algo aes256 --symmetric #{Shellwords.escape(file)}"
      #File.delete(pfile)
      Log.debug "Encrypting with: #{cmd}"
      out = `#{cmd} 2>&1`
      
      if $? != 0
        raise "Failed to encrypt file #{file}\n#{out}"
      else
        if @options[:delete_source]
          File.delete file 
          Log.debug "Deleting unencrypted chunk #{file}"
        end
      end

      Log.debug out
      output
    end

    def asymmetric(file, output)
      recipient = @options[:recipient]
      cmd = "#{@gpg_binary} #{@gpg_extra_args.join(' ')} --no-encrypt-to --no-default-recipient --recipient '#{recipient}' --encrypt #{Shellwords.escape(file)}"
      Log.debug "Encrypting with: #{cmd}"
      out = `#{cmd} 2>&1`
      
      if $? != 0
        raise "Failed to encrypt file #{file}\n#{out}"
      else
        if @options[:delete_source]
          File.delete file 
          Log.debug "Deleting unencrypted chunk #{file}"
        end
      end

      Log.debug out
      output
    end

  end

  #
  # Shamelessly stolen from Gibberish, from Mark Percival
  # so I don't have to depend on yet another gem. 
  #
  # See: https://github.com/mdp/gibberish
  #
  # Added a few small modifications:
  #
  # * Use Base64 urlsafe_encode/decode
  # 
  class CryptoEngineAES

    attr_reader :password, :size, :cipher

    # Initialize with the password
    #
    # @param [String] password
    # @param [Integer] size
    def initialize(password, size=256)
      @password = password
      @size = size
      @cipher = OpenSSL::Cipher::Cipher.new("aes-#{size}-cbc")
    end

    def encrypt(data, opts={})
      salt = generate_salt(opts[:salt])
      setup_cipher(:encrypt, salt)
      e = cipher.update(data) + cipher.final
      e = "Salted__#{salt}#{e}" #OpenSSL compatible
      opts[:binary] ? e : Base64.urlsafe_encode64(e)
    end
    alias :enc :encrypt
    alias :e :encrypt

    def decrypt(data, opts={})
      data = Base64.urlsafe_decode64(data) unless opts[:binary]
      salt = data[8..15]
      data = data[16..-1]
      setup_cipher(:decrypt, salt)
      cipher.update(data) + cipher.final
    end
    alias :dec :decrypt
    alias :d :decrypt

    private

    def generate_salt(supplied_salt)
      if supplied_salt
        return supplied_salt.to_s[0,8].ljust(8,'.')
      end
      s = ''
      8.times {s << rand(255).chr}
      s
    end

    def setup_cipher(method, salt)
      cipher.send(method)
      cipher.pkcs5_keyivgen(password, salt, 1)
    end
  end

end
