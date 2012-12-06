require 'json'
require 'csv'
require 'ctx'

module DJC

  class Mapper

    class << self
      def map(objects, &block)
        self.new(&block).map(objects)
      end
    end

    class Mapping
      attr_accessor :left, :right, :matchers, :field
      def initialize(left, right, field = nil) @left, @right, @field, @matchers = left, right, field, {} end
      def to_s() "MERGE #@right INTO #@left #{ "%(#{field}) " if field }WHERE #{@matchers.map { |k, v| "#{k} = #{v}" }.join(" AND ")}" end
    end

    class ::String
      ctx :mapping do
        def ~@() "~#{self}" end
        def -@() "^.#{self}" end

        def &(other)
          ctx[:mappings] ||= []
          if other.is_a?(Mapping)
            other.left = self
            ctx[:mappings] << other
          else
            ctx[:mappings] << Mapping.new(self, other)
          end
          p ctx[:mappings]
          self
        end
        def +(other) self & other end
        def <=(other) self & other end
        def <<(other) self & other end
        def <(other) self & other end

        def %(other) Mapping.new(nil, self, other) end
        def <=>(other) ctx[:mappings].last.matchers[self] = other end
        def method_missing(other) "#{self}.#{other}" end
      end
    end
    def method_missing(name) name.to_s end

    class ::Class
      ctx :mapping do
        def const_missing(name)
          name
        end
      end
    end

    attr_accessor :mappings
    def initialize(&block)
      ctx :mapping do
        self.instance_eval(&block)
        self.mappings = ctx[:mappings]
      end
    end

    def map(objects)
      objects = Mobj::Circle.wrap(objects)
      mappings.each do |mapping|
        matched = {}
        mapping.matchers.each_pair do |left, right|
          mapping.left.tokenize.walk(objects).each do |lobj|
            lval = left.tokenize.walk(lobj)
            mapping.right.tokenize.walk(objects).each do |robj|
              rval = right.tokenize.walk(robj)
              if lval == rval
                matched[left] ||= []
                matched[left] << [lobj, robj]
                matched[left].uniq!
              end
            end
          end
        end

        matching = matched.values.inject(matched.values.first) { |memo, val| memo & val }
        matching.each do |val|
          if mapping.field
            val.first[mapping.field] = val.last
          else
            val.first.merge!(val.last)
          end
        end
      end

      objects
    end
  end

  class Builder
    class Rule
      attr_accessor :type, :args, :block, :chain
      def initialize(type, *args, &block) @type, @args, @block, @chain = type.sym, args, block, [] end
      def to_s() "RULE:#{type.upcase}(#{args.join(', ')})#{ " +" + chain.map(&:to_s).join(" +") unless chain.empty?}" end
      def method_missing(type, *args, &block)
        chain << Rule.new(type, args, &block)
        self
      end
    end

    def initialize(&block)
      ctx :compile do
        self.instance_eval(&block)
      end
    end

    def map(&block) @mappings = block end
    alias :mappings :map

    def rules(&block)
      @dsl = DSL.new(&block)
    end
    alias :dsl :rules

    def build(objects)
      mapped = Mapper.map(objects, &@mappings)
      rows = @dsl.parse(mapped)
      keys = rows.flat_map(&:keys).uniq.sort
      CSV.generate do |csv|
        csv << keys
        rows.each do |row|
          csv << keys.map { |key| row[key] }
        end
      end
    end
  end

  def self.build(objects, &block)
    parsed = objects.inject({}) do |memo, (key, val)|
      memo[key.sym] = if val.is_a?(String)
                        val = File.read(val) if File.exists?(val)
                        JSON.parse(val, max_nesting: false,
                                        symbolize_names: true,
                                        create_additions: false,
                                        object_class: Mobj::CircleHash,
                                        array_class: Mobj::CircleRay)
                      else
                        val
                      end
      memo
    end

    Builder.new(&block).build(parsed)
  end

  class DSL < ::Object
    class ::String
      ctx(:djc_dsl_def) do
        def +@()
          +ctx[:dsl].method_missing(self.to_sym)
        end
        def -@()
          ctx[:dsl].find(self)
        end
      end
    end
    def __djc__name(rule = nil)
      @name ? "#{@name}_#{rule}" : rule
    end
    def initialize(rule = nil, parent = nil, name = parent.attempt(rule).__djc__name(rule), &block)
      @rule, @parent, @name, @capture, @finder, @nodes = rule, parent, name, false, false, []
      ctx(:djc_dsl_def) do
        ctx[:dsl] = self
        instance_eval(&block)
      end if block
    end
    def -@()
      @finder = true
      self
    end
    def +@()
      @capture = true
      self
    end
    def >(other)
      @name = other
      self
    end
    def to_str() to_s end
    def to_s(depth = 0)
      str = @capture ? "+" : ""
      str += (@rule || "ROOT").to_s
      str += "(#@name)" if @name
      str += " {\n#{@nodes.map {|n| ("  " * (depth + 1)) + n.to_s(depth + 1)}.join("\n") }\n#{"  " * depth}}" unless @nodes.empty?
      str
    end

    def find(rule, &block)
      rule = rule.inspect if rule.is_a?(Regexp)
      -method_missing(rule,&block)
    end
    alias_method :match, :find
    alias_method :with, :find

    def method_missing(name, *args, &block)
      dsl = DSL.new(name, self, *args, &block)
      @nodes << dsl
      dsl
    end

    def rule_parse(data)
      if data.is_a?(Array)
        data.flat_map do |element|
          rule_parse(element)
        end
      else
        [ { @name => @rule.to_s.walk(data) } ]
      end
    end

    def parse(data, extract = true)
      if @capture
        rule_parse(data)
      else
        data = if @finder && extract
          @rule.to_s.walk(data)
        elsif data && @rule && extract && data.is_a?(Hash)
          data[@rule]
        else
          data
        end
        if data.is_a?(Array)
          data.flat_map do |element|
            parse(element, false)
          end
        else
          @nodes.inject([]) do |rows, node|
            result = node.parse(data)
            result.flat_map do |res|
              rows.empty? ? res : rows.map { |row| row.merge(res) }
            end
          end
        end
      end
    end
  end
end