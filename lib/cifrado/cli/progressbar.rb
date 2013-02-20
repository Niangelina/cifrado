module Cifrado
  class Progressbar
    include Cifrado::Utils

    def initialize(segments, current_segment, options = {})
      @style = (options[:style] || :fancy).to_sym
      @segments = segments
      @current_segment = current_segment
    end

    def block
      if @style == :fancy
        fancy 
      elsif @style == :fast
        fast
      elsif @style == :infinite
        infinite
      else
        nil
      end
    end
    
    private
    def fancy
      require 'ruby-progressbar'
      title = (@segments == 1 ? \
               'Progress' : "Segment [#{@current_segment}/#{@segments}]")
      progressbar = nil
      read = 0
      percentage = 0
      time = Time.now.to_f
      Proc.new do |total, bytes, nchunk| 
        unless progressbar
          progressbar = ProgressBar.create :title => title, :total => 100,
                                           :format => '%t: |%B| %p%% [%E ]'
        end
        read += bytes
        percentage = (read*100/total)
        if read >= total 
          if progressbar.progress < 100
            progressbar.finish
          end
        else
          kbs = "%0.2f" % (read*8/((Time.now.to_f - time)*1024*1024))
          progressbar.title = " [#{kbs} Mb/s] #{title}"
          progressbar.progress = percentage 
        end
      end
    end

    def infinite
      read = 0
      time = Time.now.to_f
      Proc.new do |tbytes, bytes, nchunk| 
        read += bytes
        kbs = "%0.2f" % (read*8/((Time.now.to_f - time)*1024*1024))
        print "Progress (unknown total size): #{humanize_bytes(read).ljust(10)} read (#{kbs} Mb/s)".ljust(60)
        print "\r"
      end
    end

    def fast
      if @segments != 1
        title = " [#{@current_segment}/#{@segments}]"
      else
        title = " "
      end
      read = 0
      progressbar_finished = false
      time = Time.now.to_f
      Proc.new do |tbytes, bytes, nchunk| 
        read += bytes
        percentage = ((read*100.0/tbytes))
        kbs = "%0.2f" % (read*8/((Time.now.to_f - time)*1024*1024))
        print "\r"
        print "Progress (#{percentage.round}%) #{kbs} Mb/s#{title}: "
        print "#{humanize_bytes(read)} read"
        if (read + bytes) >= tbytes and !progressbar_finished
          progressbar_finished = true
          percentage = 100
          print "\r"
          print "Progress (#{percentage.round}%) #{title}: "
          puts
        end
      end
    end

  end
end
