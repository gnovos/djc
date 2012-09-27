require 'spec_helper'

describe DJC do

  describe "Array" do
    it "can walk an object tree" do

      expected = "expected"

      def expected.walk4
        to_s
      end

      obj = {
          'foo'   => 'foo',
          'walk1' => ['foo', { 'walk2' => { 'walk3' => [ 'foo', [ 'foo', 'foo', expected, 'foo'], 'foo' ] } }, 'foo' ],
          'bar'   => 'bar',
          'walk5' => { 'walk6' => 'expected2' }
      }

      ['walk1', 1, 'walk2', 'walk3', '1', 2, 'walk4' ].walk(obj).should == 'expected'
      ['walk5', 'walk6'].walk(obj).should == 'expected2'
    end

  end

  describe DJC::Rule do

    it "parses path tokens properly" do
      simple = "token"
      rule = DJC::Rule.new(simple)
      rule.paths.length.should == 1
      rule.paths.first.should == [ 'token' ]

      complex = "token[0]{subtoken{subsub}.token_with_spaces and digits 123.1|alternate|/regex[1-3]/<ref>|#literal"
      rule = DJC::Rule.new(complex)
      rule.paths.length.should == 4
      rule.paths[0].should == [ 'token', '0', 'subtoken', 'subsub', 'token_with_spaces and digits 123', '1' ]
      rule.paths[1].should == [ 'alternate' ]
      rule.paths[2].should == [ '/regex[1-3]/', '<ref>' ]
      rule.paths[3].should == [ '#literal' ]
    end
  end

  describe DJC::Builder do
    it "properly compiles column paths into rules" do
      builder = DJC::Builder.compile do |djc|
        djc['simple']  = 'token'
        djc['complex'] = 'token[subtoken]|alternate.altsubtoken'
        djc['simple']  = 'duplicate names are valid'
      end

      builder.columns.length.should == 3

      builder.columns[0].name.should == 'simple'
      builder.columns[0].rule.type.should == 'lookup'
      builder.columns[0].rule.paths[0].should == [ 'token' ]

      builder.columns[1].name.should == 'complex'
      builder.columns[1].rule.type.should == 'lookup'
      builder.columns[1].rule.paths[0].should == [ 'token', 'subtoken' ]
      builder.columns[1].rule.paths[1].should == [ 'alternate', 'altsubtoken' ]

      builder.columns[2].name.should == 'simple'
      builder.columns[2].rule.type.should == 'lookup'
      builder.columns[2].rule.paths[0].should == [ 'duplicate names are valid' ]
    end

    it "properly compiles aggregate column rules" do
      builder = DJC::Builder.compile do |djc|
        djc['sum rule']        = sum('token.path')
        djc['avg rule']        = avg('token.path')
        djc['with rule']       = with('token.path.a', 'token.path.b') { |vala, valb| }
        djc['join with rule']  = with('token.path.a', 'token.path.b').join(':')
        djc['match with rule'] = with('token.path.a').match(/matcher/)
        djc['custom rule']     = rule { |json| }
      end

      builder.columns.length.should == 6

      builder.columns[0].name.should == 'sum rule'
      builder.columns[0].rule.type.should == 'sum'
      builder.columns[0].rule.paths.length.should == 1
      builder.columns[0].rule.paths.first.paths.should == [[ 'token', 'path' ]]

      builder.columns[1].name.should == 'avg rule'
      builder.columns[1].rule.type.should == 'avg'
      builder.columns[1].rule.paths.length.should == 1
      builder.columns[1].rule.paths.first.paths.should == [[ 'token', 'path' ]]

      builder.columns[2].name.should == 'with rule'
      builder.columns[2].rule.type.should == 'with'
      builder.columns[2].rule.paths.length.should == 2

      with_rule = builder.columns[2].rule

      with_rule.paths[0].class.should == DJC::Rule
      with_rule.paths[0].type.should == 'lookup'
      with_rule.paths[0].paths.should == [[ 'token', 'path', 'a' ]]

      with_rule.paths[1].class.should == DJC::Rule
      with_rule.paths[1].type.should == 'lookup'
      with_rule.paths[1].paths.should == [[ 'token', 'path', 'b' ]]

      builder.columns[3].name.should == 'join with rule'
      builder.columns[3].rule.type.should == 'join'

      builder.columns[4].name.should == 'match with rule'
      builder.columns[4].rule.type.should == 'match'

      builder.columns[5].name.should == 'custom rule'
      builder.columns[5].rule.type.should == 'rule'

    end

    it "parses JSON via rules" do

      json = JSON.parse <<-JSON
[
  {
    "row"  : 1,
    "data" : {
      "stra" : "stringa",
      "strb" : "stringb",
      "sum"  : [ 1, 10, 100, 1000],
      "avg"  : [ 0, 0, 10, 10],
      "nil"  : null,
      "yes"  : true
    }
  },
  {
    "row"  : 2,
    "data" : {
      "stra" : "stringa",
      "strb" : "stringb",
      "sum"  : [ 2, 20, 200, 2000],
      "avg"  : [ 0, 0, 20, 20],
      "nil"  : null,
      "yes"  : true
    }
  }
]
      JSON

      builder = DJC::Builder.compile do |djc|
        djc['id']        = "row"
        djc['sums']      = sum('data.sum')
        djc['avgs']      = avg('data.avg')
        djc['yes']       = "data.nil|data.yes|data.stra"
        djc['join']      = with('data.stra', 'data.strb').join(':')
        djc['crossjoin'] = with('data.stra', 'data.sum', 'data.strb').join(':')
        djc['crosssum']  = with('data.sum', 'data.sum', 'data.sum').sum
        djc['with']      = with('data.stra') { |a| a.reverse }
        djc['multiwith'] = with('data.stra', 'data.strb') { |a, b| "#{b.reverse}#{a}" }
        djc['each']      = each('data.sum') { |sum| sum + 1 }
        djc['match']     = with('data.stra').match(/.[ai]/)
        djc['capture']   = with('data.stra').match(/(.)[ai]/)
        djc['rule']      = rule { |json| "#{json['row']}:#{json.size}" }

      end

      builder.header.should == %w(id sums avgs yes join crossjoin crosssum with multiwith each match capture rule)

      rows = builder.build(json)

      rows.length.should == 2
      rows[0].should == [1, 1111, 5.0,  true, 'stringa:stringb', ["stringa:1:stringb", "10", "100", "1000"], [3, 30, 300, 3000], 'agnirts', 'bgnirtsstringa', [2, 11, 101, 1001], ['ri', 'ga'], ['r', 'g'], '1:2' ]
      rows[1].should == [2, 2222, 10.0, true, 'stringa:stringb', ["stringa:2:stringb", "20", "200", "2000"], [6, 60, 600, 6000], 'agnirts', 'bgnirtsstringa', [3, 21, 201, 2001], ['ri', 'ga'], ['r', 'g'], '2:2' ]

    end

  end

#  it "understand djc conversion rules to convert one JSON object into CSV" do
#
#    jsonstr = <<-JSON
#{
#  "bool"    : true,
#  "null"    : null,
#  "string"  : "value",
#  "number"  : 42,
#  "array"   : [ "first array value", 814, null, "last array value" ],
#  "nums"    : [ 5, 50, 500, 5000 ],
#  "hash"    : {
#                "hash key"      : "hash value",
#                "null hash key" : null
#              },
#  "key"     : "key value",
#  "key2"    : "key2 value",
#  "other"   : "other value",
#  "each"    : [ { "a": "first val a", "b": "first val b" }, { "a": "second val a", "b": "second val b" } ],
#  "nested"  : [ "nested0",
#                {
#                  "nested1 key1" : "nested1 value1",
#                  "nested1 key2" : "nested1 value2",
#                  "nested1 key3" : "nested1 value3"
#                },
#                "nested2",
#                [ 1, 10, 100, 1000 ],
#                {
#                   "nested4 key1" : [ 2, 20, 200, 200 ],
#                   "nested4 key2" : {
#                                      "nested4_1 key1" : "nested4_1 value1",
#                                      "nested4_1 key2" : [ null, true, false, 3, "nested4_1 value2_4" ]
#                                    }
#                }
#              ]
#}
#    JSON
#
#    csv = DJC.build(jsonstr) do |djc|
#      col = '@'
#
#      def col.nxt
#        self.next!.dup
#      end
#
#      djc[col.nxt] = 'bool'
#      djc[col.nxt] = 'null'
#      djc[col.nxt] = 'number'
#      djc[col.nxt] = 'string'
#      djc[col.nxt] = 'array[3]'
#      djc[col.nxt] = 'array{1}'
#      djc[col.nxt] = 'array.0'
#      djc[col.nxt] = 'hash{hash key}'
#      djc[col.nxt] = 'hash[hash key]'
#      djc[col.nxt] = 'hash.null hash key'
#      djc[col.nxt] = 'nested[4]{nested3 key2}{nested3_1 key2}[3]'
#
#      djc[col.nxt] = with('number', 'array[1]').join
#      djc[col.nxt] = with('string', 'number').join
#      djc[col.nxt] = with('string', 'string').join
#      djc[col.nxt] = with('string', 'number') { |s, n| "#{s}:#{n}" }
#
#      djc[col.nxt] = sum('nums')
#      djc[col.nxt] = sum('nums[0,1,3]')
#      djc[col.nxt] = with('nums[1-3]').join('|')
#      djc[col.nxt] = sum('nums', 'nested[3][0]', 'nested[4]{nested3 key1}[0-2]')
#
#      djc[col.nxt] = avg('nums')
#      djc[col.nxt] = avg('nums[0,1,3]')
#
#      djc[col.nxt] = 'null|string'
#
#      djc[col.nxt] = rule { |json| json['string'].reverse }
#      djc[col.nxt] = '/other*/'
#      djc[col.nxt] = with('/key[01]/').join(':')
#
#      djc[col.nxt] = 'nums<nested.3.0>'
#
#      djc[col.nxt] = '#literal'
#
#      djc[col.nxt] = with('nums[0,1]', 'array[1]', '#literal').join(':')
#
#      djc[col.nxt] = with('each') { |ech| "#{ech['a']}|#{ech['b']}" }.join(':')
#
#      djc['A']     = 'dupcolumn'
#
#    end
#
#    csv.should_not be_nil
#    csv.should == <<-CSV
##{ header, i = [], '@'; header << i.next!.dup until i >= col; header.join(',') },A
#    CSV
#
#  end
#
#  it "can build a complete CSV from a JSON structure" do
#
#    employees = <<-JSON
#{
#  "company": "Company, Inc",
#  "employees": [
#    {"id":1,"name":{"first":"Joe","last":"Schmoe"},     "jobtitle":"CEO","address":"123 fake street","date joined":"2001-01-10","boss":null},
#    {"id":2,"name":{"first":"Jane","last":"Jabang"},    "jobtitle":"Internal Affairs Chief","address1":"123 fake street","address2":"Faketown, USA","date started":"2001-03-10","boss":1},
#    {"id":3,"name":{"first":"Mebook","last":"Garblong"},"jobtitle":"Alien Visitor Hospitality Officer","address":"123 fake street","date joined":"2001-04-10","boss":1}
#  ]
#}
#    JSON
#
#    meetings = <<-JSON
#{
#  "rooms": [
#    {"id":1,"name":"Big Meeting Room"},
#    {"id":2,"name":"Small Meeting Room"}
#  ],
#  "reserved": [
#    { "room":1, "invited": [1, 3],    "time":"15:45", "date":"2012-09-04"},
#    { "room":1, "invited": [1, 2, 3], "time":"17:45", "date":"2012-09-04"},
#    { "room":2, "invited": [2, 3],    "time":"9:45",  "date":"2012-09-05"}
#  ]
#}
#    JSON
#
#    csv = DJC.map(company:employees, meetings:meetings) do
#      join 'meetings:reserved.room' => 'meetings:rooms.id',
#           'meetings:reserved.invited.*' => 'company:employees.id'
#
#      rows('company:employees') do |djc|
#        djc['first_name'] = 'name{first}'
#        djc['last_name']  = 'name.last'
#        djc['full_name']  = with('name{first}', 'name{last}') { |first, last| "#{last}, #{first}" }
#        djc['title']      = 'jobtitle'
#        djc['joined']     = 'date started|datejoined'
#        djc['started']    = with('date started|datejoined') { |date| Date.parse(date) }
#        djc['boss_name']  = with('id<boss>{first}', 'id<boss>.last') { |first, last| "#{first} #{last}" }
#      end
#
#      rows('meetings:reserved') do |djc|
#        djc['room']      = 'room[name]'
#        djc['attending'] = with('invited') { |invited| "#{invited['first']} #{invited['last']}" }.join(',')
#      end
#
#    end
#
#    csv.should_not be_nil
#    csv.length.should == 2
#    csv.first.should == <<-CSV
#first_name,last_name,full_name,title,joined,started,boss_name
#Joe,Schmoe,"Schmoe, Joe",CEO,2001-01-10,2001-01-10,
#Jane,Jabang,"Jabang, Jane",Internal Affairs Chief,2001-03-10,2001-03-10,Joe Schmoe
#Mebook,Garblong,"Garblong Mebook,Alien Visitor Hospitality Officer,2001-04-10,2001-04-10,Joe Schmoe
#    CSV
#    csv.last.should == <<-CSV
#room,attending
#Big Meeting Room,"Joe Schmoe,Mebook Garblong"
#Big Meeting Room,"Joe Schmoe,Jane Jabang,Mebook Garblong"
#Small Meeting Room,"Jane Jabang,Mebook Garblong"
#    CSV
#
#  end


end
