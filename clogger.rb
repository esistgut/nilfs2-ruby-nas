require 'net/smtp'


class CLogger
    def initialize
        @methods = []
    end
    
    def log(message)
        @message = message
        @methods.each { |x| send(x) }
    end
    
    def add_smtp_out(smtp, port, from, to, subject)
        @mail = {}
        @mail[:smtp], @mail[:port], @mail[:from], @mail[:to], @mail[:subject] = smtp, port, from, to, subject
        @methods.push(:mail)
    end
    
    def mail
        Net::SMTP.start(@mail[:smtp], @mail[:port]) { |smtp|
            smtp.open_message_stream(@mail[:from], @mail[:to]) { |f|
                f.puts "From: #{@mail[:from]}"
                f.puts "To: #{@mail[:to]}"
                f.puts "Subject: #{@mail[:subject]}"
                f.puts ""
                f.puts "log message follows: #{@message}"
            }
        }
    end
end


def test
    require 'yaml'
    c = YAML.load_file(File.dirname(__FILE__) + "/conf.yaml")
    l = CLogger.new
    l.add_smtp_out(c['config']['mail_log']['smtp'], c['config']['mail_log']['port'], c['config']['mail_log']['from'], c['config']['mail_log']['to'], c['config']['mail_log']['subject'])
    l.log("test mail")
end

test if $0 == __FILE__
