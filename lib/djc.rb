require 'json'
require 'csv'
require 'sender'
require 'ctx'

module DJC

  class ::Object
    def djrent(rent = :djrent) @djrent = rent unless rent == :djrent; @djrent end
    def djroot() djrent.nil? ? self : djrent.djroot end
  end

  class ::Array
    def sequester(lim = 1) compact.size <= lim ? compact.first : self end
  end

  class Circle < Hash

    def initialize
      super
      @index = 0
    end

    def <<(val)
      self[@index] = val
      @index += 1
    end

    def []=(*keys, val)
      val.djrent(self)
      keys.each do |key|
        if key.is_a?(Range)
          key.to_a.each{ |k| self[k]= val }
        else
          @index = key + 1 if key.is_a?(Fixnum) && key > @index
          store(key.sym, val)
        end
      end
    end

    alias_method :lookup, :[]
    def [](*keys) keys.map { |key| self.lookup(key.sym) }.sequester
    end

    def method_missing(name, *args, &block)
      self.has_key?(name) ? self[name] : super(name, *args, &block)
    end

  end

  class Token
    def initialize(type, *args, &block)
      @type, @path, @options = type.to_sym, nil, {}
      tokens = []
      args.each do |arg|
        if arg.is_a? Hash
          @options.merge!(arg)
        elsif arg.is_a? String
          tokens << arg.sym
        else
          tokens << arg
        end
      end
      @path = tokens.sequester
    end

    def to_s
      "#{@type.to_s.upcase}(#@path#{ " => #@options" unless @options.empty?})"
    end

    def extract(obj, path)
      if obj.is_a?(Array)
        if path == :*
          obj
        else
          obj.map { |o| extract(o, path)}
        end
      else
        if path.is_a?(Array)
          path.map { |pth| obj[pth.sym] }
        else
          obj[path.sym]
        end
      end
    end

    def walk(obj, root = obj)
      val = case @type
              when :literal
                @path.to_s
              when :path
                extract(obj, @path)
              when :regex
                obj.keys.map { |key| key if key.match(@path) }.compact.map{|key| obj[key]}
              when :any
                @path.return_first { |token| token.walk(obj, root) }
              when :all
                matches = @path.map { |token| token.walk(obj, root) }
                matches.compact.size == @path.size ? matches : nil
              when :each
                @path.map { |token| token.walk(obj, root) }
              when :lookup
                lookup = @path.walk(obj)
                if lookup.is_a?(Array)
                  lookup.flatten.map { |lu| lu.tokenize.walk(root) }.flatten(1)
                else
                  lookup.tokenize.walk(root)
                end
              when :inverse
                #xxx hrd
              when :root
                tree = [@path].flatten
                while (path = tree.shift)
                  obj = path.walk(obj)
                end
                obj.is_a?(Array) ? obj.flatten : obj
            end

      @options[:indexes] ? val.values_at(*@options[:indexes])  : val
    end
  end

  class ::String
    def ~@
      "~#{self}"
    end

    def tokenize
      tokens = []
      scan(/\~([^\.]+)|\/(.*?)\/|\{\{(.*?)\}\}|([^\.\[]+)(?:\[([\d\+\.,-]+)\])?/).each do |literal, regex, lookup, path, indexes|
        if literal
          tokens << Token.new(:literal, literal)
        elsif lookup
          tokens << Token.new(:lookup, lookup.tokenize)
        elsif regex
          tokens << Token.new(:regex, Regexp.new(regex))
        elsif path
          eachs = path.split(",")
          ors = path.split("|")
          ands = path.split("&")
          if eachs.size > 1
            tokens << Token.new(:each, eachs.map { |token| token.tokenize() })
          elsif ands.size > 1
            tokens << Token.new(:all, ands.map { |token| token.tokenize() })
          elsif ors.size > 1
            tokens << Token.new(:any, ors.map { |token| token.tokenize() })
          end

          unless ands.size + ors.size + eachs.size > 3
            options = {}
            options[:indexes] = indexes.scan(/(\d+)(?:(?:\.\.(\.)?|-?)(-?\d+|\+))?/).map do |start, exc, len|
              len.nil? ? start.to_i : (Range.new(start.to_i, (len == "+" ? -1 : len.to_i), !exc.nil?))
            end if indexes

            if path[0] == '!'
              tokens << Token.new(:inverse, Token.new(:path, path[1..-1].sym, options))
            else
              tokens << Token.new(:path, path.sym, options)
            end
          end
        end
      end

      tokens.size == 1 ? tokens.first : Token.new(:root, tokens)

    end
  end

  #xxx where types of mappings needed (so not all are "and")

  class Mapper

    class << self
      def map(objects, &block)
        self.new(&block).map(objects)
      end
    end

    class Mapping
      attr_accessor :left, :right, :matchers
      def initialize(left, right) @left, @right, @matchers = left, right, {} end
      def to_s() "MERGE #@right INTO #@left WHERE #{@matchers.map { |k, v| "#{k} = #{v}" }.join(" AND ")}" end
    end

    class ::String
      ctx :mapping do
        def <(other)
          puts ":: '#{@@contexts}'  #{self} < #{other}"
          ctx[:mappings] ||= []
          ctx[:mappings] << Mapping.new(self, other)
        end

        def ==(other)
          puts ":: '#{@@contexts}' #{self} == #{other}"
          if ctx[:mappings]
            ctx[:mappings].last.matchers[self] = other
          end

        end
      end
    end

    def merge(*args)
    end

    def where(*args)
    end

    attr_accessor :mappings
    def initialize(&block)
      ctx :mapping do
        self.instance_eval(&block)
        self.mappings = ctx[:mappings]
      end
    end

    def map(objects)

      mappings.each do |mapping|
        puts "left  #{mapping.left}"
        puts "  tokens #{mapping.left.tokenize}"
        puts "  walked #{mapping.left.tokenize.walk(objects)}"

        puts "right #{mapping.right}"
        puts "  tokens #{mapping.right.tokenize}"
        puts "  walked #{mapping.right.tokenize.walk(objects)}"

      end

      objects
    end
  end


end