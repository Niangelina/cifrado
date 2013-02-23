require 'cifrado'
require 'yaml'
require 'securerandom'
require 'fileutils'
require 'digest/md5'

include Cifrado
  
unless ENV['DEBUG']
  Cifrado::Log.level = Logger::ERROR
end

def client
  conf = YAML.load_file File.expand_path("~/.cifradorc")
  client = SwiftClient.new  :username => conf[:username],
                            :api_key  => conf[:password],
                            :auth_url => conf[:auth_url],
                            :connection_options => { :ssl_verify_peer => false }
end

def test_container
  client.service.directories.create :key => test_container_name
end

def test_container_name
  'cifrado-tests'
end

def test_container_segments_name
  'cifrado-tests_segments'
end

def test_container_segments
  client.service.directories.create :key => test_container_segments_name
end

# Size in KB
def create_bin_payload size, filename = nil
  if filename
    tmp_file = filename
  else
    tmp_file = "/tmp/cifrado-test-payload-#{SecureRandom.hex}"
  end
  target_dir = File.dirname(tmp_file)
  unless File.directory?(target_dir)
    FileUtils.mkdir_p target_dir
  end
  out = `dd if=/dev/urandom of=#{tmp_file} bs=1K count=#{size} > /dev/null 2>&1`
  raise "Error creating #{size}MB binary payload" unless $? == 0
  tmp_file
end

def create_text_payload text
  tmp_file = "/tmp/cifrado-test-payload-#{SecureRandom.hex}"
  File.open tmp_file, 'w' do |f|
    f.puts text
  end
  tmp_file
end

def clean_test_payloads
  Dir["/tmp/cifrado-test-payload-*"].each do |f|
    File.delete f
  end
end

def clean_test_container
  if dir = test_container
    dir.files.each do |f|
      f.destroy
    end
  end
  if dir = test_container_segments
    dir.files.each do |f|
      f.destroy
    end
  end
end

def passphrase
  'foobar'
end

def cleanup
  clean_test_payloads
  clean_test_container
  Dir["/tmp/cifrado*"].each { |f| FileUtils.rm_rf f }
  Dir[File.join(ENV['HOME'], ".cache/cifrado") + "/*segments*"].each { |f| FileUtils.rm_rf f }
end

def tmpfile
  "/tmp/cifrado-tests-#{SecureRandom.hex}"
end

at_exit do
  puts "Cleaning up..."
  cleanup
  test_container_segments.destroy
  test_container.destroy
end
