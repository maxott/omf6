module OmfEc::Context
  class GroupContext
    attr_accessor :group
    attr_accessor :guard
    attr_accessor :operation

    def initialize(opts)
      self.group = opts.delete(:group)
      self.guard = opts
      self
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

      o_m = OmfEc.comm.__send__(op_name, send_to) do |m|
        m.element(:guard) do |g|
          self.guard.each_pair do |k, v|
            g.property(k, v)
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
          release_m = OmfEc.comm.release_message(self.group) { |m| m.element('resource_id', uid) }

          release_m.publish self.group

          release_m.on_inform_released do |m|
            info "#{m.resource_id} released"
            r = OmfEc.exp.state.find { |v| v[:uid] == m.resource_id }
            r[:released] = true unless r.nil?
            block.call if block
            Experiment.instance.process_events
          end
        end

        r = OmfEc.exp.state.find { |v| v[:uid] == i.read_property(:uid) }
        unless r.nil?
          i.each_property do |p|
            p_key = p.attr('key').to_sym
            r[p_key] = i.read_property(p_key)
          end
        end
        Experiment.instance.process_events
      end

      o_m.on_inform_failed do |i|
        warn "RC reports failure: '#{i.read_content("reason")}'"
      end
    end
  end
end
