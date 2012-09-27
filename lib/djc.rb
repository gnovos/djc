require 'json'
require 'csv'

module DJC

  class ::String
    def ~@
      "##{self}"
    end

  end

  class ::Array

    def walk(obj)
      path = self.dup
      key = path.shift.to_s

      val = if obj.is_a? Array
              if key == '*'
                if path.empty?
                  obj
                else
                  sub = obj.map do |inner|
                    path.dup.walk(inner)
                  end
                  path.clear
                  sub
                end
              elsif /^[\d,-]+$/.match(key)
                selected = key.split(',').map do |dex|
                  range = /(\d+)(?:-|\.\.\.?)(\d+)/.match(dex)
                  if range
                    range = range.captures
                    obj[range.first.to_i..range.last.to_i]
                  else
                    obj[dex.to_i]
                  end
                end.flatten
                selected.size == 1 ? selected.first : selected
              end
            elsif obj.is_a? Hash
              match = key[/\/(.*)\//, 1]
              if match.nil?
                obj[key]
              else
                found = obj.keys.select { |k| Regexp.new(match).match(k) }
                found = found.map { |k| path.empty? ? obj[k] : path.walk(obj[k]) }
                path.clear
                found = found.first if found.size < 2
                found
              end
            elsif obj.respond_to? key
              obj.send(key)
            end

      path.empty? ? val : path.walk(val)
    end

    def collate
      collated = [[]]
      fill = {}
      each_with_index do |obj, index|
        if obj.is_a?(Array)
          obj.each_with_index do |item, row|
            collated[row] ||= []
            collated[row][index] = item
          end
        end
      end
      collated.each do |row|
        each_with_index do |obj, index|
          unless obj.is_a?(Array)
            row[index] = obj
          end
        end
      end
      collated.size == 1 ? collated.first : collated
    end


    def cross
      crossed = [[]]

      each do |obj|
        if obj.is_a?(Array)
          adding = []
          obj.each_with_index do |item, index|
            crossed.each do |cross|
              row = cross.dup
              row << item
              adding << row
            end
          end
          crossed = adding
        else
          crossed.each { |cross| cross << obj }
        end
      end
      crossed.size == 1 ? crossed.first : crossed
    end
  end

  class Rule
    def parse(paths)
      rules = paths.split('|').map do |path|
        path.scan(/\/[^\/]+\/|\<[^\<]\>|[^\[\]\{\}\|\.]+/)
      end

      rules
    end

    attr_reader :paths, :type, :block
    def initialize(type='lookup', rules, &block)
      if rules.is_a?(String) && rules[0] == '#'
        @type, @block, @paths = 'literal', proc { rules[1..-1] }, nil
      else
        @type, @block, @paths = type, block, rules.is_a?(String) ? parse(rules) : rules
      end
    end

    def sum
      @type, @block = 'sum', proc { |array| array.map(&:to_i).inject(0, :+) if array }
      self
    end

    def avg
      @type, @block = 'avg', proc { |array| ( array.map(&:to_i).inject(0.0, :+) / array.size) if array }
      self
    end

    def each(&each_block)
      @type, @block = 'each', proc { |array| array.map { |val| each_block.call(val) } if array }
      self
    end

    def join(sep = '')
      @type, @block = 'join', proc { |vals| vals.is_a?(Array) ? vals.compact.join(sep) : vals }
      self
    end

    def match(matcher)
      @type, @block = 'match', proc { |val| val.scan(matcher).flatten }
      self
    end

    def apply(obj)
      value = nil
      if type == 'lookup'
        walker = paths.dup
        value = nil
        while value.nil? && path = walker.shift
          value = path.walk(obj)
        end
        value
      else
        if paths.nil? || paths.empty?
          value = block.call(obj)
        elsif paths.length > 1
          value = [[]]
          paths.each_with_index do |rule, index|
            val = rule.apply(obj)
            if val.is_a?(Array)
              val.each_with_index do |v, row|
                value[row] ||= []
                value[row][index] ||= []
                value[row][index] = v
              end
            else
              value.first << val
            end
          end
          value = value.map { |val| block.call(val) } unless block.nil?
          value = value.first if value.length == 1
          value
        else
          value = paths.first.apply(obj)
          value = block.call(value) unless block.nil?
        end
      end
      value
    end

  end

  class Column
    attr_reader :name, :rule
    def initialize(name, rule)
      @name, @rule = name, rule.is_a?(Rule) ? rule : Rule.new(rule)
    end
  end

  class Builder
    def self.compile(path=nil, &block)
      builder = Builder.new(path)
      builder.instance_eval &block
      builder
    end

    def initialize(path = nil)
      @path = Rule.new(path) if path
    end

    attr_reader :columns
    def []=(column, rule)
      @columns ||= []
      @columns << Column.new(column, rule)
    end

    def header
      columns.map { |column| column.name }
    end

    def sum(*paths)
      with(*paths).sum
    end

    def avg(*paths)
      with(*paths).avg
    end

    def each(*paths, &block)
      with(*paths).each(&block)
    end

    def with(*paths, &block)
      Rule.new('with', paths.map { |path| Rule.new(path) }, &block)
    end

    def rule(&block)
      Rule.new('rule', nil, &block)
    end

    def build(json)
      json = @path.apply(json) if @path
      rows = []
      if json.is_a? Array
        json.each do |row|
          row = @columns.map do |column|
            column.rule.apply(row)
          end
          p row
          rows << row
        end
      else
        rows << @columns.map do |column|
          column.rule.apply(json)
        end
      end
      rows
    end

  end

  class << self

    def build(json = nil, &block)
      json = JSON.parse(json) if json.is_a?(String)

      builder = Builder.compile(&block)

      out = CSV.generate do |csv|
        csv << builder.header
        builder.build(json).each do |row|
          p "row is #{row}"
          csv << row
        end
      end
      out
    end
  end

end