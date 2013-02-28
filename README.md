# Cifrado

**WARNING** 

The current Cifrado release is experimental. Use at your own risk.

OpenStack Swift CLI with built in (GPG) encryption.

## Features available in Cifrado 0.1

* Uploading/downloading files and directories to OpenStack Swift.
* Asymmetric/Symmetric transparent encryption/decryption of files
  when uploading/downloading using GnuPG.
* Segmented uploads (splitting the file in multiple segments).
* Progressbar!
* Bandwidth limits when uploading/downloading stuff.
* Music streaming (streams the mp3/ogg files available in a container
  and plays them using mplayer if available).
* Regular list/delete/stat commands.
* Ruby 1.8.7, 1.9.X and 2.0 compatibility

Cifrado has a built-in help command:

```
[9648][rubiojr.blueleaf] cifrado help
Tasks:
  cifrado delete CONTAINER [OBJECT]      # Delete specific container or object
  cifrado download [CONTAINER] [OBJECT]  # Download container, objects
  cifrado help [TASK]                    # Describe available tasks or one s...
  cifrado jukebox CONTAINER              # Play music randomly from the targ...
  cifrado list [CONTAINER]               # List containers and objects
  cifrado post CONTAINER [DESCRIPTION]   # Create a container
  cifrado set-acl CONTAINER --acl=ACL    # Set an ACL on containers and objects
  cifrado setup                          # Initial Cifrado configuration
  cifrado stat [CONTAINER] [OBJECT]      # Displays information for the acco...
  cifrado upload CONTAINER FILE          # Upload a file

Options:
  [--username=USERNAME]  
  [--quiet=QUIET]        
  [--password=PASSWORD]  
  [--auth-url=AUTH_URL]  
  [--tenant=TENANT]      
  [--config=CONFIG]      
  [--region=REGION]      
  [--insecure]           # Insecure SSL connections
```

## Installation

### Installing the Ubuntu packages (recommended)

Open a terminal and type:

```
sudo add-apt-repository ppa:rubiojr/cifrado
sudo apt-get update
sudo apt-get install cifrado
```

You'll also need GnuPG and MPlayer installed if you want to have
music streaming and encryption support enabled in Cifrado
(GnuPG and the agent is pre-installed in a regular Ubuntu 
installation):

    sudo apt-get install mplayer gnupg gnupg-agent

### Installing via rubygems

Needs rubygems and ruby available in your system.

Ubuntu installation:

    sudo apt-get install ruby rubygems

Install the gem:

    sudo gem install cifrado

## Usage

### Seting up Cifrado for the first time

Use 'cifrado setup' to configure Cifrado for the first time.

Note that it's not strictly required to save the options or running the
setup process. If you do so, you'll not be asked for the username,
password, auth_url and other parameters required to run Cifrado.

The setup command will ask you the OpenStack Swift connection
information:

    $ cifrado setup
    Running cifrado setup...
    Please provide OpenStack/Rackspace credentials.
    
    Cifrado can save this settings in /home/rubiojr/.config/cifrado/cifradorc
    for later use.
    The settings (password included) are saved unencrypted.
    
    Username: user
    Tenant: my_tenant
    Password: 
    Auth URL: https://identity.example.net/v2.0/tokens
    Do you want to save these settings? (y/n)  



### Uploading/Downloading files with Cifrado

#### Uploading files

Uploading a single file, LICENSE.txt, to container 'test':

```
$ cifrado upload test LICENSE.txt

Uploading LICENSE.txt (1.04 KB)
[0.00 Mb/s] Progress: |=====================| 100% [Time: 00:00:02 ]
```

Uploading a directory (recursively) to container 'test':

```
$ cifrado upload test tmp

Uploading tmp/LICENSE.txt (1.04 KB)
 [0.00 Mb/s] Progress: |=====================| 100% [Time: 00:00:02 ]
Uploading tmp/cifrado.gemspec (1.14 KB)
 [0.00 Mb/s] Progress: |=====================| 100% [Time: 00:00:02 ]
```

Limiting upload speed with --bwlimit:

```
$ cifrado upload --bwlimit 0.10 test pkg/cifrado-0.1.gem

Uploading pkg/cifrado-0.1.gem (163.00 KB)
 [0.09 Mb/s] Progress: |=====================| 100% [Time: 00:00:14 ]
```

The bwlimit data rate unit is Mb/s. The same --bwlimit option can
be used when downloading files.

Uploading big files using segments:

```
$ cifrado upload --segments 3 test pkg/cifrado-0.1.gem 
Segmenting file, 3 segments...
Uploading cifrado-0.1.gem segments
Uploading segment 1/3 (56.00 KB)
 [0.00 Mb/s] Segment [1/3]: |================| 100% [Time: 00:00:02 ]
Uploading segment 2/3 (56.00 KB)
 [0.00 Mb/s] Segment [2/3]: |================| 100% [Time: 00:00:02 ]
Uploading segment 3/3 (51.00 KB)
 [0.00 Mb/s] Segment [3/3]: |================| 100% [Time: 00:00:03 ]
```

Note that segments are automatically reassembled by Swift when you
download the object. That is, to download cifrado-0.1.gem from the
test container, download it like any other regular object.

#### Downloading files

#### Encryption support

**Symmetric Encryption**

    cifrado upload --insecure \
                   --encrypt symmetric \
                   my-container audio.mp3

Cifrado will ask you for the password.

You could also specify the password as an argument (not recommended):

    cifrado upload --insecure \
                   --encrypt s:foobar \
                   my-container audio.mp3

**Asymmetric Encryption ('Traditional' GPG encryption)**

    cifrado upload --insecure \
                   --encrypt a:rubiojr@frameos.org \
                   my-container audio.mp3

Or using the key ID:

    cifrado upload --insecure \
                   --encrypt a:F345BE74 \
                   my-container audio.mp3

#### Streaming the music available in a container

Needs mplayer installed:

    sudo apt-get install mplayer

Play the files available in the 'music' container:

```
$ cifrado jukebox music

Cifrado Jukebox
---------------

Ctrl-C once   -> next song
Ctrl-C twice  -> quit

Playing song
  * spotify/Los Lobos/La Bamba.ogg
```

## Known issues

* Foo
* Bar
* A lot of them

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
