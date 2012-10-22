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
              elsif /^[\d,\+-\.]+$/.match(key)
                selected = nil
                key.split('|').each do |option|
                  locators = option.split(',').map do |dex|
                    range = /(?<start>\d+)(?:-|\+|\.\.(?<exclusive>\.)?)?(?<end>-?\d+)/.match(dex)
                    range ? Range.new(range['start'].to_i, (range['end'] || -1).to_i, range['exclusive']) : dex.to_i
                  end
                  selected = obj.values_at(*locators)
                  break if selected
                end
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
      regex = /\/[^\/]+\//
      lookup = /\<[^\<]\>/
      indexes = /(?:-?\d+(?:(?:\.\.\.?|-|\+)(?:-?\d+)?)?,?)+/
      node = /[^\[\]\{\}\.]+/
      paths.split('||').map do |path|
        path.scan(/#{regex}|#{lookup}|#{indexes}|#{node}/)
      end

    end

    attr_reader :paths, :blocks
    def initialize(rules, &block)
      if rules.is_a?(String) && rules[0] == '#'
        @blocks, @paths = [proc { rules[1..-1] }], nil
      else
        @blocks, @paths = [block].compact, (rules.is_a?(String) ? parse(rules) : rules)
      end
    end

    def to_s
      "RULE(#{paths}:#{blocks})"
    end

    def sum
      @blocks << proc { |array| array.map(&:to_i).inject(0, :+) if array }
      self
    end

    def avg
      @blocks << proc { |array| ( array.map(&:to_i).inject(0.0, :+) / array.size) if array }
      self
    end

    def each(&each_block)
      @blocks <<  proc { |array| array.map { |val| each_block.call(val) } if array }
      self
    end

    def join(sep = '')
      @blocks << proc { |vals| vals.is_a?(Array) ? vals.compact.join(sep) : vals }
      self
    end

    def sort(&sort_block)
      @blocks << proc { |sort| sort.is_a?(Array) ? sort.compact.sort(&sort_block) : (sort.nil? ? nil : sort.sort(&sort_block)) }
      self
    end

    def match(matcher)
      @blocks << proc do |val|
        if val
          if val.is_a?(Array)
            val.compact.map do |v|
              match = v.scan(matcher).flatten
              match.size == 1 ? match.first : match
            end
          else
            match = val.scan(matcher).flatten
            match.size == 1 ? match.first : match
          end
        end
      end
      self
    end

    def apply(obj)
      if @blocks.empty?
        walker = paths.dup
        value = nil
        while value.nil? && (path = walker.shift)
          value = path.walk(obj)
        end
        value
      else
        if paths.nil? || paths.empty?
          value = blocks.inject(obj) { |val, block| block.call(val) }
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
          value = value.map { |val| blocks.inject(val) { |v, block| block.call(v) }} unless blocks.empty?
          value = value.first if value.length == 1
          value
        else
          value = paths.first.apply(obj)
          value = blocks.inject(value) { |val, block| block.call(val) } unless blocks.empty?
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
      Rule.new(paths.map { |path| Rule.new(path) }, &block)
    end

    def rule(&block)
      Rule.new(nil, &block)
    end

    def build(json)
      json = @path.apply(json) if @path
      rows = []
      if json.is_a? Array
        json.each do |row|
          row = @columns.map do |column|
            column.rule.apply(row)
          end
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
          csv << row
        end
      end
      out
    end
  end

end