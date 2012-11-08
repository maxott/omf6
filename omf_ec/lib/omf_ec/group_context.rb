module OmfEc
  class GroupContext
    attr_accessor :group
    attr_accessor :guard
    attr_accessor :operation

    def initialize(opts)
      self.group = opts.delete(:group)
      self.guard = opts
      self
    end

    def exp
      Experiment.instance
    end

    def comm
      Experiment.instance.comm
    end

    def [](opts = {})
      self.guard.merge!(opts)
      self
    end

    def method_missing(name, *args, &block)
      if name =~ /(.+)=/
        self.operation = :configure
        name = $1
      elsif name =~ /release/
        self.operation = :release
      else
        self.operation = :request
      end
      send_message(name, *args, &block)
    end

    def send_message(name, value = nil, &block)
      send_to = self.group
      send_to = send_to + "_#{self.guard[:type]}" if self.guard[:type]

      # if release, we need to request resource ids first
      op_name = self.operation == :release ? "request_message" : "#{self.operation}_message"

      o_m = comm.__send__(op_name, send_to) do |m|
        m.element(:guard) do |g|
          self.guard.each_pair do |k, v|
            g.element(k, v)
          end
        end

        unless self.operation == :release
          m.property(name, value)
        end

        unless self.operation == :configure
          m.property(:uid)
          m.property(:hrn)
        end
      end

      o_m.publish send_to

      o_m.on_inform_status do |i|
        if self.operation == :release
          uid = i.read_property(:uid)
          info "Going to release #{uid}"
          release_m = comm.release_message(self.group) { |m| m.element('resource_id', uid) }

          release_m.publish self.group

          release_m.on_inform_released do |m|
            info "#{m.resource_id} released"
            r = exp.state.find { |v| v[:uid] == m.resource_id }
            r[:released] = true unless r.nil?
            block.call if block
            Experiment.instance.process_events
          end
        end

        r = exp.state.find { |v| v[:uid] == i.read_property(:uid) }
        unless r.nil?
          i.each_property do |p|
            r[p.attr('key').to_sym] = p.content.ducktype
          end
        end
        Experiment.instance.process_events
      end
    end
  end
end