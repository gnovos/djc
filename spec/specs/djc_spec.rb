require 'spec_helper'

describe DJC do

  describe String do
    it "can convery to literal using unary ~ operator" do
      str = ~"str"
      str.should == "#str"
    end

  end

  describe Array do

    it "can select the first block that return non-nil" do

      count = 0
      [1,2,3,4,5].select_first { |i| count += 1; i == 3 ? "found" : nil }.should == "found"
      count.should == 3;

    end

    it "can walk an object tree" do

      expected = "expected"

      def expected.walk4
        to_s
      end

      obj = {
          'foo'   => 'foo',
          'walk1' => ['foo', { 'walk2' => { 'walk3' => [ 'foo', [ 'foo', 'foo', expected, 'foo'], 'foo' ] } }, 'foo' ],
          'bar'   => 'bar',
          'walk5' => { 'walk6' => 'expected2' },
          'walk7' => [ 'walk8', 'walk9', 'foo', 'walk0' ]
      }

      ['walk1', 1, 'walk2', 'walk3', '1', 2, 'walk4' ].walk(obj).should == 'expected'
      ['walk5', 'walk6'].walk(obj).should == 'expected2'
      ['walk7', '0-1'].walk(obj).should == [ 'walk8', 'walk9']
      ['walk7', '0,1,3'].walk(obj).should == [ 'walk8', 'walk9', 'walk0']
      ['walk7', '*'].walk(obj).should == [ 'walk8', 'walk9', 'foo', 'walk0' ]

    end

    it "can crossjoin subarrays to form a multidimensional array" do
      uncrossed = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0].cross
      uncrossed.should == [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]

      crossed = [1, 2, [3, 4], 5, 6, [7, 8, 9], 0].cross
      crossed.should == [
          [1, 2, 3, 5, 6, 7, 0],
          [1, 2, 4, 5, 6, 7, 0],

          [1, 2, 3, 5, 6, 8, 0],
          [1, 2, 4, 5, 6, 8, 0],

          [1, 2, 3, 5, 6, 9, 0],
          [1, 2, 4, 5, 6, 9, 0]
      ]

      single = [[1, 2, 3]].cross
      single.should == [
          [1], [2], [3]
      ]

    end

    it "can collate inner arrays" do
      uncollated = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0].collate
      uncollated.should == [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]

      single = [[1, 2, 3]].collate
      single.should == [
          [1], [2], [3]
      ]

      collated = [1, 2, [3, 4], 5, 6, [7, 8, 9], 0].collate
      collated.should == [
          [1, 2, 3, 5, 6, 7, 0],
          [1, 2, 4, 5, 6, 8, 0],

          [1, 2, nil, 5, 6, 9, 0]
      ]

    end

  end

  describe DJC::Rule do

    it "parses path tokens properly" do
      simple = "token"
      rule = DJC::Rule.new(simple)
      rule.paths.length.should == 1
      rule.paths.first.should == [ 'token' ]

      complex = "token[0]{subtoken{subsub}.token_with_spaces and digits 123.1||alternate||/regex[1-3]/<ref>||#literal"
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
        djc['complex'] = 'token[subtoken]||alternate.altsubtoken'
        djc['simple']  = 'duplicate names are valid'
      end

      builder.columns.length.should == 3

      builder.columns[0].name.should == 'simple'
      builder.columns[0].rule.paths[0].should == [ 'token' ]

      builder.columns[1].name.should == 'complex'
      builder.columns[1].rule.paths[0].should == [ 'token', 'subtoken' ]
      builder.columns[1].rule.paths[1].should == [ 'alternate', 'altsubtoken' ]

      builder.columns[2].name.should == 'simple'
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
      builder.columns[0].rule.paths.length.should == 1
      builder.columns[0].rule.paths.first.paths.should == [[ 'token', 'path' ]]

      builder.columns[1].name.should == 'avg rule'
      builder.columns[1].rule.paths.length.should == 1
      builder.columns[1].rule.paths.first.paths.should == [[ 'token', 'path' ]]

      builder.columns[2].name.should == 'with rule'
      builder.columns[2].rule.paths.length.should == 2

      with_rule = builder.columns[2].rule

      with_rule.paths[0].class.should == DJC::Rule
      with_rule.paths[0].paths.should == [[ 'token', 'path', 'a' ]]

      with_rule.paths[1].class.should == DJC::Rule
      with_rule.paths[1].paths.should == [[ 'token', 'path', 'b' ]]

      builder.columns[3].name.should == 'join with rule'

      builder.columns[4].name.should == 'match with rule'

      builder.columns[5].name.should == 'custom rule'

    end

  it "parses JSON via rules" do

    json = JSON.parse <<-JSON
{
  "rows" : [
    {
      "row"  : 1,
      "data" : {
        "stra" : "stringa",
        "strb" : "stringb",
        "sum"  : [ 1, 10, 100, 1000],
        "avg"  : [ 0, 0, 10, 10],
        "sel"  : [ 1, 2, 3, 4, 5, 6, 7, 8 ],
        "nil"  : null,
        "yes"  : true,
        "sub1" : { "key1" : "val11", "key2" : "val12" },
        "sub2" : { "key1" : "val21", "key2" : "val22" }
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
        "yes"  : true,
        "sub1" : { "key1" : "val11", "key2" : "val12" }
      }
    }
  ]
}
    JSON

    builder = DJC::Builder.compile('rows') do |djc|
      djc['id']           = 'row'
      djc['sums']         = sum('data.sum')
      djc['avgs']         = avg('data.avg')
      djc['yes']          = 'data.nil||data.yes||data.stra'
      djc['join']         = with('data.stra', 'data.strb').join(':')
      djc['crossjoin']    = with('data.stra', 'data.sum', 'data.strb').join(':')
      djc['crosssum']     = with('data.sum', 'data.sum', 'data.sum').sum
      djc['with']         = with('data.stra') { |a| a.reverse }
      djc['multiwith']    = with('data.stra', 'data.strb') { |a, b| "#{b.reverse}#{a}" }
      djc['each']         = each('data.sum') { |sum| sum + 1 }
      djc['match']        = with('data.stra').match(/.[ai]/)
      djc['capture']      = with('data.stra').match(/(.)[ai]/)
      djc['rule']         = rule { |json| "#{json['row']}:#{json.size}" }
      djc['regx']         = '/ro./'
      djc['multiregx']    = 'data./str./'
      djc['cmplxregx']    = 'data./sub[12]/./key[12]/'
      djc['literal']      = ~'literal string'
      djc['partialsum']   = sum('data.sum[0-1]')
      djc['selectivesum'] = sum('data.sum[0,2,3]')
      djc['selectindex']  = 'data.sel[0,2-4,6]'
    end

    rows = builder.build(json)

    rows.length.should == 2
    rows[0].should == [1, 1111, 5.0,  true, 'stringa:stringb', ['stringa:1:stringb', '10', '100', '1000'], [3, 30, 300, 3000], 'agnirts', 'bgnirtsstringa', [2, 11, 101, 1001], ['ri', 'ga'], ['r', 'g'], '1:2', 1, ['stringa', 'stringb'], [['val11', 'val12'], ['val21', 'val22']], 'literal string', 11, 1101, [ 1, 3, 4, 5, 7 ] ]
    rows[1].should == [2, 2222, 10.0, true, 'stringa:stringb', ['stringa:2:stringb', '20', '200', '2000'], [6, 60, 600, 6000], 'agnirts', 'bgnirtsstringa', [3, 21, 201, 2001], ['ri', 'ga'], ['r', 'g'], '2:2', 2, ['stringa', 'stringb'], ['val11', 'val12'], 'literal string', 22, 2202, nil ]

    builder.header.should == %w(id sums avgs yes join crossjoin crosssum with multiwith each match capture rule regx multiregx cmplxregx literal partialsum selectivesum selectindex)

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
#    $col = 0
#
#    csv = DJC.build(jsonstr) do |djc|
#
#      def nxt
#        $col = $col.next
#        "col#{$col}"
#      end
#
#      djc[nxt] = 'bool'
#      djc[nxt] = 'null'
#      djc[nxt] = 'number'
#      djc[nxt] = 'string'
#      djc[nxt] = 'array[3]'
#      djc[nxt] = 'array{1}'
#      djc[nxt] = 'array.0'
#      djc[nxt] = 'hash{hash key}'
#      djc[nxt] = 'hash[hash key]'
#      djc[nxt] = 'hash.null hash key'
#      djc[nxt] = 'nested[4]{nested3 key2}{nested3_1 key2}[3]'
#
#      djc[nxt] = with('number', 'array[1]').join
#      djc[nxt] = with('string', 'number').join
#      djc[nxt] = with('string', 'string').join
#      djc[nxt] = with('string', 'number') { |s, n| "#{s}:#{n}" }
#
#      djc[nxt] = sum('nums')
#      djc[nxt] = sum('nums[0,1,3]')
#      djc[nxt] = with('nums[1-3]').join('|')
#      djc[nxt] = sum('nums', 'nested[3][0]', 'nested[4]{nested3 key1}[0-2]') #brokwn
#
#      djc[nxt] = avg('nums')
#      djc[nxt] = avg('nums[0,1,3]')
#
#      djc[nxt] = 'null||string'
#
#      djc[nxt] = rule { |json| json['string'].reverse }
#      djc[nxt] = '/other*/'
#      djc[nxt] = with('/key[01]/').join(':')
#
#      djc[nxt] = ~'literal'
#
#      djc[nxt] = with('nums[0,1]', 'array[1]', '#literal').join(':') #brokwn
#
#      djc[nxt] = with('each.*.a','each.*.b').join(':') #brokn
#
#      djc['col0']     = ~'dupcolumn'
#
#    end
#
#    csv.should_not be_nil
#    csv.should == <<-CSV
#col1,col2,col3,col4,col5,col6,col7,col8,col9,col10,col11,col12,col13,col14,col15,col16,col17,col18,col19,col20,col21,col22,col23,col24,col25,col26,col27,col28,col0
#true,,42,value,last array value,814,first array value,hash value,hash value,,,42814,value42,valuevalue,value:42,5555,5055,50|500|5000,6,1388.75,1685.0,value,eulav,other value,,literal,5:814:literal,first val a:first val b,dupcolumn
#true,,42,value,last array value,814,first array value,hash value,hash value,,,42814,value42,valuevalue,value:42,5555,5055,50|500|5000,50,1388.75,1685.0,value,eulav,other value,,literal,5:814:literal,first val a:first val b,dupcolumn
#true,,42,value,last array value,814,first array value,hash value,hash value,,,42814,value42,valuevalue,value:42,5555,5055,50|500|5000,500,1388.75,1685.0,value,eulav,other value,,literal,5:814:literal,first val a:first val b,dupcolumn
#true,,42,value,last array value,814,first array value,hash value,hash value,,,42814,value42,valuevalue,value:42,5555,5055,50|500|5000,5000,1388.75,1685.0,value,eulav,other value,,literal,5:814:literal,first val a:first val b,dupcolumn
#true,,42,value,last array value,814,first array value,hash value,hash value,,,42814,value42,valuevalue,value:42,5555,5055,50|500|5000,6,1388.75,1685.0,value,eulav,other value,,literal,50,first val a:first val b,dupcolumn
#true,,42,value,last array value,814,first array value,hash value,hash value,,,42814,value42,valuevalue,value:42,5555,5055,50|500|5000,50,1388.75,1685.0,value,eulav,other value,,literal,50,first val a:first val b,dupcolumn
#true,,42,value,last array value,814,first array value,hash value,hash value,,,42814,value42,valuevalue,value:42,5555,5055,50|500|5000,500,1388.75,1685.0,value,eulav,other value,,literal,50,first val a:first val b,dupcolumn
#true,,42,value,last array value,814,first array value,hash value,hash value,,,42814,value42,valuevalue,value:42,5555,5055,50|500|5000,5000,1388.75,1685.0,value,eulav,other value,,literal,50,first val a:first val b,dupcolumn
#true,,42,value,last array value,814,first array value,hash value,hash value,,,42814,value42,valuevalue,value:42,5555,5055,50|500|5000,6,1388.75,1685.0,value,eulav,other value,,literal,5:814:literal,second val a:second val b,dupcolumn
#true,,42,value,last array value,814,first array value,hash value,hash value,,,42814,value42,valuevalue,value:42,5555,5055,50|500|5000,50,1388.75,1685.0,value,eulav,other value,,literal,5:814:literal,second val a:second val b,dupcolumn
#true,,42,value,last array value,814,first array value,hash value,hash value,,,42814,value42,valuevalue,value:42,5555,5055,50|500|5000,500,1388.75,1685.0,value,eulav,other value,,literal,5:814:literal,second val a:second val b,dupcolumn
#true,,42,value,last array value,814,first array value,hash value,hash value,,,42814,value42,valuevalue,value:42,5555,5055,50|500|5000,5000,1388.75,1685.0,value,eulav,other value,,literal,5:814:literal,second val a:second val b,dupcolumn
#true,,42,value,last array value,814,first array value,hash value,hash value,,,42814,value42,valuevalue,value:42,5555,5055,50|500|5000,6,1388.75,1685.0,value,eulav,other value,,literal,50,second val a:second val b,dupcolumn
#true,,42,value,last array value,814,first array value,hash value,hash value,,,42814,value42,valuevalue,value:42,5555,5055,50|500|5000,50,1388.75,1685.0,value,eulav,other value,,literal,50,second val a:second val b,dupcolumn
#true,,42,value,last array value,814,first array value,hash value,hash value,,,42814,value42,valuevalue,value:42,5555,5055,50|500|5000,500,1388.75,1685.0,value,eulav,other value,,literal,50,second val a:second val b,dupcolumn
#true,,42,value,last array value,814,first array value,hash value,hash value,,,42814,value42,valuevalue,value:42,5555,5055,50|500|5000,5000,1388.75,1685.0,value,eulav,other value,,literal,50,second val a:second val b,dupcolumn
#    CSV
#
#  end

#  it "can build a complete CSV from a JSON structure" do
#
#    json = <<-JSON
#[
#  {"company": "Company Inc",
#   "employees": [
#     {"id":1,"name":{"first":"Joe","last":"Schmoe"},     "jobtitle":"CEO","address":"123 fake street","date joined":"2001-01-10","boss":null},
#     {"id":2,"name":{"first":"Jane","last":"Jabang"},    "jobtitle":"Internal Affairs Chief","address1":"123 fake street","address2":"Faketown, USA","date started":"2001-03-10","boss":1},
#     {"id":3,"name":{"first":"Mebook","last":"Garblong"},"jobtitle":"Alien Visitor Hospitality Officer","address":"123 fake street","date joined":"2001-04-10","boss":1}
#  ]},
#  {"company": "Other Company DotCom",
#   "employees": [
#     {"id":11,"name":{"first":"Dame","last":"Edna"},     "jobtitle":"CEO","address":"123 fake street","date joined":"2001-01-10","boss":null},
#     {"id":21,"name":{"first":"Senor","last":"Whoozit"}, "jobtitle":"Senior Engineer","address1":"123 fake street","address2":"Faketown, USA","date started":"2001-03-10","boss":1}
#  ]}
#]
#    JSON
#
#    csv = DJC.build(json) do |djc|
#      djc['company']   = 'company'
#      djc['full name'] = with('employees.*.name.first', 'employees.*.name.last').join(' ')
#      djc['title']     = 'employees.*.jobtitle'
#    end
#
#    puts csv
#
#
#    csv.should_not be_nil
#    csv.should == <<-CSV
#company,full name,title
#Company Inc,Joe Schmoe,CEO
#Company Inc,Jane Jabang,Internal Affairs Chief
#Company Inc,Mebook Garblong,Alien Visitor Hospitality Officer
#Other Company DotCom,Dame Edna,CEO
#Other Company DotCom,Senor Whoozit,Senior Engineer
#    CSV
#
#  end


  it "parses JSON starting with array" do

    json = JSON.parse <<-JSON
[
    { "id": 10, "name": { "first": "bob",   "last": "sanchez" }, "date_joined": "2001",  "phone":         ["555-1111", "555-2222", "555-3333"],
      "sales": [50, 10, 30],
      "email_address": "Dirty <sanchez@address.com>",
      "account_ids": [40, 44, 15, 100, 225, 9916, 318 ]
    },
    { "id": 20, "name": { "first": "Steph", "last": "Whatzit" }, "year_joined": "2004" , "phone":         ["555-1111", "555-4444", "555-6666", "555-7777"],
      "email_address": "steph@address.com",
      "account_ids": [30, 55, 15, 10, 25, 9916, 3189 ] 
    },
    { "id": 30, "name": { "given": "joe",   "last": "biden"   },                         "phone_numbers": ["555-1111", "555-0000", "555-5555", "555-9999", "555-8888"],
      "email_address": "Joe <joe@address.com>" ,
      "account_ids": [90, 66, 15, 100, 225, 916, 318, 22, 1828, 2, 9 ] ,
      "friends": [ { "name": "joe", "history": { "level": "acquaintance" } }, { "name": "bob", "past": { "level": "best" } }, { "name": "jim" } ]
    }
]
    JSON

    csv = DJC.build(json) do |djc|
      djc['id']            = 'id'
      djc['full_name']     = with('name.first|given', 'name.last').join(' ')
      djc['company']       = ~"CompanySoft, Inc."
      djc['regex']         = '/.*_joined/'
      djc['total_sales']   = sum("sales")
      djc['avg_sales']     = avg("sales")
      djc['phone_numbers'] = with("/^phone*/[0,2]") { |primary, secondary| "main:#{primary} fax:#{secondary}"}
      djc['person_phones'] = with("phone[1-5]").join(",")
      djc['accounts']      = with("account_ids[1,2..4,8+]").join(':')
      djc['crosssum']      = with('sales[0]', 'account_ids[2]').sum
      djc['email_addys']   = with('email_address').match(/[^\<\s]+\@[^\>\s]+/i)
      djc['rule']          = rule { |json| "#{json['id']}:#{json.size}" }
      djc['friends']       = with("friends.*.name").sort.join(':')
      djc['friendship']    = with("friends.*.history|past.level").sort.join(':')
    end

    csv.should == <<-CSV
id,full_name,company,regex,total_sales,avg_sales,phone_numbers,person_phones,accounts,crosssum,email_addys,rule,friends,friendship
10,bob sanchez,"CompanySoft, Inc.",2001,90,30.0,main:555-1111 fax:555-3333,"555-2222,555-3333",44:15:100:225,65,sanchez@address.com,10:7,,
20,Steph Whatzit,"CompanySoft, Inc.",2004,,,main:555-1111 fax:555-6666,"555-4444,555-6666,555-7777",55:15:10:25,15,steph@address.com,20:6,,
30,joe biden,"CompanySoft, Inc.",,,,main:555-1111 fax:555-5555,,66:15:100:225:1828,15,joe@address.com,30:6,bob:jim:joe,acquaintance:best
    CSV

  end

end
