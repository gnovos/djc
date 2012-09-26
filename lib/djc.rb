require 'json'
require 'csv'

module DJC

  class Rule
    def parse(paths)
        rules = paths.split('|')
        rules.map do |path|
          path.scan(/\/[^\/]+\/|\<[^\<]\>|[^\[\]\{\}\|\.]+/)
        end
    end

    attr_reader :paths, :type, :block
    def initialize(type='lookup', rules, &block)
      @type, @block, @paths = type, block, rules.is_a?(String) ? parse(rules) : rules
    end
  end

  class Column
    attr_reader :name, :rule
    def initialize(name, rule)
      @name, @rule = name, rule.is_a?(Rule) ? rule : Rule.new(rule)
    end
  end

  class Builder
    def self.build(&block)
      builder = Builder.new
      builder.instance_eval &block
      builder
    end

    attr_reader :columns
    def []=(column, rule)
      @columns ||= []
      @columns << Column.new(column, rule)
    end

    def sum(path)
      Rule.new('sum', path)
    end

    def avg(path)
      Rule.new('avg', path)
    end

    def with(*paths, &block)
      Rule.new('with', paths.map { |path| Rule.new(path) }, &block)
    end

  end

  class << self

    def join(token_map)

    end

    def row(tokens, &block)
    end

    def col(tokens, &block)
    end

    def rows(tokens, &block)
    end


    def build(json = nil, &block)
#xxx    json = JSON.parse(json) if json.is_a?(String)

      builder = Builder.new

      block.call(builder)

      out = CSV.generate do |csv|
        csv << builder.headers
        builder.build(json).each do |row|
          csv << row
        end
      end
      out
    end

  end



end