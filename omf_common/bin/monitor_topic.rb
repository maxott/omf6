#
DESCR = %{
Monitor a set of resources (topics) and print all observed messages.

If the 'follow-children' flag is set, automatically add all resources
created by the monitored resources to the monitor set. Please note
that there will be a delay until the new monitors are in place which
can result in missed messages.
}

require 'omf_common'

OP_MODE = :development

opts = {
  communication: {
    url: 'amqp://srv.mytestbed.net'
  },
  eventloop: { type: :em},
  logging: {
    level: 'info'
  }  
}

observed_topic = nil
$follow_children = true

op = OptionParser.new
op.banner = "Usage: #{op.program_name} [options] topic1 topic2 ...\n#{DESCR}\n"
op.on '-c', '--comms-url URL', "URL to communication layer [#{opts[:communication][:url]}]" do |url|
  opts[:communication][:url] = url
end
op.on '-f', "--[no-]follow-children", "Follow all newly created resources [#{$follow_children}]" do |flag|
  $follow_children = flag
end
op.on '-d', '--debug', "Set logging to DEBUG level" do
  opts[:logging][:level] = 'debug'
end
op.on_tail('-h', "--help", "Show this message") { $stderr.puts op; exit }
observed_topics = op.parse(ARGV)

unless observed_topics
  $stderr.puts 'Missing declaration of topics to follow'
  $stderr.puts op
  exit(-1)
end

$observed_topics = {}

def observe(tname, comm)
  return if $observed_topics.key? tname
  
  info "Observing '#{tname}'"
  $observed_topics[tname] = true
  comm.subscribe(tname) do |topic|
    topic.on_message do |msg|
      puts "#{tname}   <#{msg.type}(#{msg.inform_type})>    #{msg.inspect}"
      msg.each_property do |name, value|
        puts "    #{name}: #{value}"
      end
      puts "------"
      
      if $follow_children && msg.inform_type == 'created'
        #puts ">>>>>> #{msg}"
        observe(msg[:resource_id], comm)
      end
    end
  end
end

OmfCommon.init(OP_MODE, opts) do |el|
  OmfCommon.comm.on_connected do |comm|
    observed_topics.each do |topic|
      observe(topic, comm)
    end
  end
end