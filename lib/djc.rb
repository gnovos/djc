require 'json'
require 'csv'
require 'sender'
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
    class Column
      attr_accessor :name
      def initialize(name) @name = name end
      def to_s() "COLUMN(#{name.to_s})" end
    end
    class Rule
      attr_accessor :type, :args, :block, :chain
      def initialize(type, *args, &block) @type, @args, @block, @chain = type.sym, args, block, [] end
      def to_s() "RULE:#{type.upcase}(#{args.join(', ')})#{ " +" + chain.map(&:to_s).join(" +") unless chain.empty?}" end
      def method_missing(type, *args, &block)
        chain << Rule.new(type, args, &block)
        self
      end
    end
    class ::String
      ctx :compile do
        def <=(other)
          ctx[:columns] ||= {}
          ctx[:columns][Column.new(self)] = other.is_a?(Rule) ? other : Rule.new(:path, other.to_s)
        end
        def -@() "^.#{self}" end
        def method_missing(other) "#{self}.#{other}" end
        def match(matcher, &block) Rule.new(:path, self).match(matcher, &block) end
        def join(matcher, &block) Rule.new(:path, self).join(matcher, &block) end
        def each(&block) Rule.new(:path, self).each(&block) end
        def sum() Rule.new(:path, self).sum() end
        def avg() Rule.new(:path, self).avg() end
      end
    end
    def method_missing(name) name.to_s end

    def initialize(&block)
      ctx :compile do
        self.instance_eval(&block)
        pp ctx[:columns]
      end
    end

    def map(&block) @mappings = block end
    alias :mappings :map

    def rules(&block)
      instance_eval(&block)
    end

    def build(objects)
      Mapper.map(objects, &@mappings)
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



end