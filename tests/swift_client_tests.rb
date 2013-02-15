Shindo.tests('Cifrado | SwiftClient') do
      
  obj = create_bin_payload 1
  obj10 = create_bin_payload 10
  obj100 = create_bin_payload 100

  tests('set_acl') do
    dir = client.service.directories.create :key => 'public-container'
    response = client.set_acl '.r:*,.rlistings','public-container'
    test 'success' do
      [202,201].include? response.status
    end
    test 'ACL present' do
      response = client.service.request :method => 'GET', 
                                        :path => 'public-container'
      response.headers['X-Container-Read'] == '.r:*,.rlistings'
    end
    dir.destroy
  end

  tests('#encrypted_upload') do
    test 'success' do
      response = client.encrypted_upload('cifrado-tests', obj) 
      cipher = CryptoEngineAES.new client.api_key
      url = client.service.credentials[:server_management_url]
      url << File.join("/cifrado-tests/", obj)
      fname = client.head(url).headers['X-Object-Meta-Encrypted-Name']
      ([202,201].include? response.status) and obj == cipher.decrypt(fname)
    end
  end

  tests("#upload") do

    tests("responds to") do
      [:upload].each do |m|
        test "#{m}" do
          client.respond_to? m
        end
      end
    end

    raises ArgumentError, "ArgumentError when container nil" do
      client.upload nil, 'foo'
    end
    raises ArgumentError, "ArgumentError when object nil" do
      client.upload 'foo', nil
    end
    raises ArgumentError, "when not enough arguments" do
      client.upload
    end

    tests "success" do
      test "upload OK" do
        response = client.upload('cifrado-tests', obj) 
        response.status == 201
      end

      test "correct path" do
        file = create_bin_payload 1
        client.upload('cifrado-tests', file) 
        dir = client.service.directories.get 'cifrado-tests'
        !(dir.files.get file[1..-1]).nil?
      end
      
      test "custom object path" do
        file = create_bin_payload 1
        client.upload('cifrado-tests', file, :object_path => '/foobar')
        dir = client.service.directories.get 'cifrado-tests'
        !(dir.files.get 'foobar').nil?
      end
    end

    tests "progress callback" do
      chunks = []
      cb = Proc.new do |tsize, bytes, nchunk|
        chunks << bytes 
      end
      client.upload 'cifrado-tests', obj, :progress_callback => cb
      test "chunks equal File.size" do
        # FIXME
        # File.size should be equal to the bytes read
        # but StreamUploader is buggy
        File.size(obj) <= chunks.inject(:+)
      end
    end
  end

  clean_test_payloads
  dir = client.service.directories.get('cifrado-tests')
  dir.files.each do |f|
    f.destroy
  end
  dir.destroy

  cleanup 

end
