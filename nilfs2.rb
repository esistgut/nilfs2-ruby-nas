#!/usr/bin/ruby1.9.1


unless $LOAD_PATH.include?(File.expand_path(File.dirname(__FILE__)))
    $LOAD_PATH.unshift(File.expand_path(File.dirname(__FILE__)))
end

require 'time'
require 'optparse'
require 'yaml'

require 'clogger'


class LinuxMount
    def find_by_dev(device)
        r = Array.new
        get_mounts().each { |m| if m[:dev] == device then r.push(m) end }
        return r
    end
    
    def find_by_path(path)
        r = Array.new
        get_mounts().each { |m| if m[:path] == path then r.push(m) end }
        return r
    end
    
    def mount(m)
        fs = m[:fs] != nil ? "-t "+m[:fs] : ""
        opts = ""
        m[:opts].each { |x, y| opts += (y != nil ? ",#{x}=#{y}": ",#{x}" ) }
        opts = "-o #{opts[1..-1]}" unless opts == ""
        `mount #{fs} #{opts} #{m[:dev]} #{m[:path]}`
    end
    
    def umount(m)
        `umount #{m[:path]}`
        #puts "umount #{m[:path]}"
    end
    
    def get_mounts()
        f = File.open("/proc/mounts")
        r = Array.new
        begin
            while (l = f.readline) do
                a = l.split
                b = a[3].split(",")
                o = {}
                b.each { |bi| o[bi.split("=")[0]] = bi.split("=")[1] }
                r.push({:dev => a[0], :path => a[1], :fs => a[2], :opts => o})
            end
        rescue EOFError
            f.close
        end
        return r
    end
end


class NILFS2
    def initialize(device)
        raise IOError, "can't find device file" unless File.exists?(device)
        @device = device
    end
    
    def get_checkpoints()
        t = `lscp #{@device}`
        r = Array.new
        t.split("\n")[1..-1].each do |l|
            a = l.split
            time = Time.parse("#{a[1]} #{a[2]}")
            r.push({:CNO => a[0], :MODE => a[3], :FLG => a[4],
            :NBLKINC => a[5], :ICNT => a[6], :time => time})
        end
        return r
    end

    def get_snapshots()
        r = Array.new
        get_checkpoints.each { |c| r.push(c) if c[:MODE] == "ss" }
        return r
    end

    def ss_to_mount(snapshot, path)
        return {:dev => @device, :path => path, :fs => "nilfs2", :opts => {"ro"=>nil, "cp" => snapshot[:CNO]} }
    end
    
    def make_checkpoint(snapshot=false)
        snapshot ? `mkcp -s #{@device}` : `mkcp #{@device}`
    end
    
    def make_snapshot()
        make_checkpoint(true)
    end
    
    def remove_checkpoint(checkpoint)
        `chcp cp #{@device} #{checkpoint[:CNO]}` if checkpoint[:MODE] == "ss"
        `rmcp #{@device} #{checkpoint[:CNO]}`
    end
    
    def get_total_space()
        `df -Pk #{@device} |grep ^/ | awk '{print $2;}'`.to_i * 1024
    end
    
    def get_used_space()
        `df -Pk #{@device} |grep ^/ | awk '{print $3;}'`.to_i * 1024
    end

    def get_free_space()
        `df -Pk #{@device} |grep ^/ | awk '{print $4;}'`.to_i * 1024
    end
    
    def get_free_space_percent()
        #total:100=used:x
        get_free_space()*100/get_total_space()
    end
end


class Nas
    def initialize()
        c = YAML.load_file(File.dirname(__FILE__) + "/conf.yaml")
        @n = NILFS2.new(c['config']['dev'])
        @m = LinuxMount.new
        @l = CLogger.new
        @usb = c['config']['usb']
        @data_path = c['config']['data_path']
        @ss_path =  c['config']['snapshots_path']
        @l.add_smtp_out(c['config']['mail_log']['smtp'], c['config']['mail_log']['port'], c['config']['mail_log']['from'], c['config']['mail_log']['to'], c['config']['mail_log']['subject'])
    end

    def bootstrap()
        mount_all_snapshots()
    end

    def sync_usb()
        `mount #{@usb}`
        if $? == 0 then
            `rsync -r --delete #{@data_path} #{@usb}`
            `umount #{@usb}`
        else
            raise "failed to mount usb drive" 
        end
    end

    def collect()
        `/etc/init.d/samba stop`
        umount_all_snapshots()
        @m.remove_checkpoint(@m.get_checkpoints[0]) while @n.get_free_space_percent < 10
        if (@n.get_free_space_percent < 10) and @m.get_checkpoints.empty? then
            @l.log("end of space")
            raise("end of space")
        end
        @n.make_snapshot()
        mount_all_snapshots()
        `/etc/init.d/samba start`
        sync_usb if not @usb.nil? 
    end

    def umount_all_snapshots()
        @m.get_mounts.each do |p|
            if p[:fs] == "nilfs2" and p[:opts]["cp"] != nil then
                @m.umount(p)
                `rm -rf #{p[:path]}` if p[:path].include? @ss_path
            end
        end
    end

    def mount_all_snapshots()
        umount_all_snapshots()
        `rm -rf #{@ss_path}/*`
        @n.get_snapshots.each do |s|
            mp = "#{@ss_path}#{ to_mount_time(s[:time]) }"
            `mkdir #{mp}`
            @m.mount(@n.ss_to_mount(s, mp))
        end
    end

    def to_mount_time(t)
        t.strftime("%Y_%m_%d___%H_%M_%S")
    end


    def test()
        cps = @n.get_checkpoints
        puts @n.get_free_space_percent
        #@n.remove_checkpoint(cps[6])
        #cps.each { |c| puts @n.ss_to_mount(c, "lol") }
        #umount_all_snapshots()
        

	    #puts @n.get_snapshots()
	    #@n.make_snapshot
	    #puts @n.get_snapshots
        #puts m.find_by_path("/mnt/tmpa")
        #puts @m.get_mounts()
        #@m.mount({:dev => "/dev/loop0", :path => "/mnt/tmpb/5", :fs => "nilfs2", :opts => {"ro"=>nil, "cp" => 5} })
    end

end




options = {}
 
optparse = OptionParser.new do |opts|
    opts.banner = "Usage: nilfs2nas.rb -c or -b"
    
    options[:collect] = false
    opts.on( '-c', '--collect', 'Nas daily routine' ) do
        options[:collect] = true
    end
    
    options[:bootstrap] = false
    opts.on( '-b', '--bootstrap', 'Boot operations' ) do
        options[:bootstrap] = true
    end
    

    options[:test] = false
    opts.on( '-r', '--test', 'Test' ) do
        options[:test] = true
    end


    options[:umount] = false
    opts.on( '-u', '--umount', 'Umount snapshots' ) do
        options[:umount] = true
    end

    opts.on( '-h', '--help', 'Display this screen' ) do
        puts opts
        exit
    end
end

#.parse! remove used options, .parse does not
optparse.parse!


if options[:collect] ^ options [:bootstrap] ^ options[:test] ^ options[:umount] then
    n = Nas.new
    n.collect if options[:collect]
    n.bootstrap if options[:bootstrap]
    n.umount_all_snapshots if options[:umount]
    n.test if options[:test]
    
else
    puts "only one command at a time"
end
