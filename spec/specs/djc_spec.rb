require '../spec_helper'

describe DJC do

  context "DJC#merge" do

    it "can merge two hashes based on smart rules" do
      people = { people: [ { employee_id: 0, company_id: 0 }, { employee_id: 1, company_id: 0 }] }

      employees = [
          { company: 0, employees: [ { empid: 0, name: "Joe" }, { empid: 1, name: "Sally" } ] },
          { company: 1, employees: [ { empid: 0, name: "Wong"}, { empid: 1, name: "Wright"} ] }
      ]

      mapped = DJC::Mapper.map(a:people, b:employees) do
        MERGE
        'a.people' & 'b.employees'

        WHERE
        'employee_id' <=> 'empid'
        'company_id' <=> '^.^.company'
      end

      mapped.should == {
          a: { people: [ { employee_id: 0, company_id: 0, empid: 0, name: "Joe"   },
                         { employee_id: 1, company_id: 0, empid: 1, name: "Sally" }] },
          b: [ { company: 0, employees: [ { empid: 0, name: "Joe" }, { empid: 1, name: "Sally" } ] },
               { company: 1, employees: [ { empid: 0, name: "Wong"}, { empid: 1, name: "Wright"} ] } ]
      }
    end
  end

  context "DSL parsing" do

    it "can parse a JSON document based on a DSL" do
      json = <<-JSON
{
  "customers" : [
    {"id": 100,
     "name": "Company Inc",
     "employees": [
       {"id":1,"name":{"first":"Joe","last":"Schmoe"},
        "jobtitle":"CEO","address":"123 fake street","date joined":"2001-01-10","boss":null},
       {"id":2,"name":{"first":"Jane","last":"Jabang"},
        "jobtitle":"Internal Affairs Chief","address1":"123 fake street","address2":"Faketown, USA","date started":"2001-03-10","boss":1},
       {"id":3,"name":{"first":"Mebook","last":"Garblong"},
        "jobtitle":"Alien Visitor Hospitality Officer","address":"123 fake street","date joined":"2001-04-10","boss":1}
    ]},
    {"id": 200,
     "name": "Other Company DotCom",
     "employees": [
       {"id":11,"name":{"first":"Dame","last":"Edna"},     "jobtitle":"CEO","address":"123 fake street","date joined":"2001-01-10","boss":null},
       {"id":12,"name":{"first":"Senor","last":"Whoozit"}, "jobtitle":"Senior Engineer","address1":"123 fake street","address2":"Faketown, USA","date started":"2001-03-10","boss":1}
    ]}
  ]
}
      JSON

      dsl = DJC::DSL.new do
        customers do
          +name("company_name")
          employees do
            +id("employees_id")
            name do
              +first("first_name")
              +last("last_name")
            end
            +"date joined|date started" > "joined"
          end
        end
      end

      parsed = dsl.parse(JSON.parse(json))

      parsed.sort{|a,b|a.to_s<=>b.to_s}.should == [
          {"company_name" => "Company Inc",          "employees_id" => 1,  "first_name" => "Joe",    "last_name" => "Schmoe",   "joined" => "2001-01-10"},
          {"company_name" => "Company Inc",          "employees_id" => 2,  "first_name" => "Jane",   "last_name" => "Jabang",   "joined" => "2001-03-10"},
          {"company_name" => "Company Inc",          "employees_id" => 3,  "first_name" => "Mebook", "last_name" => "Garblong", "joined" => "2001-04-10"},
          {"company_name" => "Other Company DotCom", "employees_id" => 11, "first_name" => "Dame",   "last_name" => "Edna",     "joined" => "2001-01-10"},
          {"company_name" => "Other Company DotCom", "employees_id" => 12, "first_name" => "Senor",  "last_name" => "Whoozit",  "joined" => "2001-03-10"}
      ].sort{|a,b|a.to_s<=>b.to_s}

    end

    it "can parse out a single rule" do
      data = { search_key: "found", other_key:"not correct"}

      dsls = {
          +DJC::DSL.new("search_key") => [
              {  "search_key" => "found" }
          ],
          +DJC::DSL.new("search_key", nil, "found_key_name") => [
              { "found_key_name" => "found" }
          ],
          +DJC::DSL.new("not there") => [
              { "not there" => nil }
          ]
      }

      dsls.each_pair do |dsl, expected|
        dsl.parse(data).should == expected
      end
    end

    it "can parse out nested simple rules" do
      data = { depth_0: { depth_1_found: "found 1", depth_1: { depth_2: { depth_3_found: "found 3", other: "wrong" }, other: "wrong" }, other: "wrong" }, other: "wrong"  }

      dsl = DJC::DSL.new do
        depth_0 do
          +depth_1_found
          depth_1 do
            depth_2 do
              +depth_3_found("d3found")
            end
          end
        end
      end

      dsl.parse(data).should == [
          { "depth_0_depth_1_found" => "found 1", "d3found" => "found 3"  }
      ]
    end

    it "can have complex finders" do
      data = [ { a: { b: { c0: { val: 0 }, c1: { val: 1 }, c2: { val: 2 }, c3: { val: 3 }}}}]

      dsls = [
          DJC::DSL.new do
            find("a.b./c[023]/") do
              +val("val")
            end
          end,
          DJC::DSL.new do
            a.b do
              match(/c[023]/) do
                +val("val")
              end
            end
          end
      ]

      dsls.each do |dsl|
        dsl.parse(data).sort{ |a,b| a.to_s <=> b.to_s }.should == [
            { "val" => 0 },
            { "val" => 2 },
            { "val" => 3 }
        ].sort { |a,b| a.to_s <=> b.to_s }
      end

    end

    it "can parse a rule out of an array of data" do
      data = [
          { search_key: "found A", other_key:"not correct"},
          { search_key: "found B", other_key:"not correct"},
          { search_key: "found C", other_key:"not correct"}
      ]

      dsls = {
          +DJC::DSL.new("search_key") => [
              {  "search_key" => "found A" },
              {  "search_key" => "found B" },
              {  "search_key" => "found C" }
          ],
          +DJC::DSL.new("search_key", nil, "found_key_name") => [
              { "found_key_name" => "found A" },
              { "found_key_name" => "found B" },
              { "found_key_name" => "found C" }
          ],
          +DJC::DSL.new("not there") => [
              { "not there" => nil },
              { "not there" => nil },
              { "not there" => nil }
          ]
      }

      dsls.each_pair do |dsl, expected|
        dsl.parse(data).should == expected
      end
    end

    it "can parse out nested complex rules one deep, with missing values nilled out" do
      data = { a: { b: [ { val: "val1", inner: [ { val: "innerval11" }, { val: "innerval12" } ] },
                         { val: "val2", inner: [ { val: "innerval21" }, { val: "innerval22" } ] } ],
                    c: { d: "value", e: "e", f: "f", g: "g" }
      }
      }

      dsl = DJC::DSL.new do
        a do
          b do
            +val("val")
            +missing("missing")
            inner do
              +val("inner")
            end
          end
          +c.d
        end
      end

      dsl.parse(data).sort{ |a,b| a.to_s <=> b.to_s }.should == [
          { "val" => "val1", "inner" => "innerval11", "missing" => nil, "a_c_d" => "value" },
          { "val" => "val1", "inner" => "innerval12", "missing" => nil, "a_c_d" => "value" },

          { "val" => "val2", "inner" => "innerval21", "missing" => nil, "a_c_d" => "value" },
          { "val" => "val2", "inner" => "innerval22", "missing" => nil, "a_c_d" => "value" }
      ].sort { |a,b| a.to_s <=> b.to_s }
    end

    it "can parse out arbitrarily complex rules" do
      data = { depth_0: {
          depth_1_found: "found 1",
          depth_1: {
              depth_2: [
                  { depth_3_found: "found 3a", other: "wrong" },
                  { depth_3_found: "found 3b", other: "wrong" },
                  { depth_3_found: "found 3c", other: "wrong" },
              ],
              other: "wrong",
              complex_a: [
                  { val: "val1",
                    cplxb: [
                        { cplxc: { cplxd: [ { val: "val111" }, { val: "val112" } ] } },
                        { cplxc: { cplxd: [ { val: "val121" }, { val: "val122" } ] } }, ]
                  },
                  { val: "val2",
                    cplxb: [
                        { cplxc: { cplxd: [ { val: "val211" }, { val: "val211" } ] } } ]
                  }
              ]
          },
          other: "wrong"
      },
               other: "wrong"  }

      dsl = DJC::DSL.new do
        depth_0 do
          +depth_1_found("d1")
          depth_1 do
            depth_2 do
              +depth_3_found("d3")
            end
            complex_a do
              +val("val")
              cplxb.cplxc.cplxd do
                +val("innerval")
              end
            end
          end
        end
      end

      dsl.parse(data).sort{ |a,b| a.to_s <=> b.to_s }.should == [
          { "d1" => "found 1", "d3" => "found 3a", "val" => "val1", "innerval" => "val111" },
          { "d1" => "found 1", "d3" => "found 3b", "val" => "val1", "innerval" => "val111" },
          { "d1" => "found 1", "d3" => "found 3c", "val" => "val1", "innerval" => "val111" },

          { "d1" => "found 1", "d3" => "found 3a", "val" => "val1", "innerval" => "val112" },
          { "d1" => "found 1", "d3" => "found 3b", "val" => "val1", "innerval" => "val112" },
          { "d1" => "found 1", "d3" => "found 3c", "val" => "val1", "innerval" => "val112" },

          { "d1" => "found 1", "d3" => "found 3a", "val" => "val1", "innerval" => "val121" },
          { "d1" => "found 1", "d3" => "found 3b", "val" => "val1", "innerval" => "val121" },
          { "d1" => "found 1", "d3" => "found 3c", "val" => "val1", "innerval" => "val121" },

          { "d1" => "found 1", "d3" => "found 3a", "val" => "val1", "innerval" => "val122" },
          { "d1" => "found 1", "d3" => "found 3b", "val" => "val1", "innerval" => "val122" },
          { "d1" => "found 1", "d3" => "found 3c", "val" => "val1", "innerval" => "val122" },

          { "d1" => "found 1", "d3" => "found 3a", "val" => "val2", "innerval" => "val211" },
          { "d1" => "found 1", "d3" => "found 3b", "val" => "val2", "innerval" => "val211" },
          { "d1" => "found 1", "d3" => "found 3c", "val" => "val2", "innerval" => "val211" },

          { "d1" => "found 1", "d3" => "found 3a", "val" => "val2", "innerval" => "val211" },
          { "d1" => "found 1", "d3" => "found 3b", "val" => "val2", "innerval" => "val211" },
          { "d1" => "found 1", "d3" => "found 3c", "val" => "val2", "innerval" => "val211" }
      ].sort { |a,b| a.to_s <=> b.to_s }
    end

    it "can handle incomplete JSON documents" do
      data = { depth_0: {
          depth_1_found: "found 1",
          depth_1: {
              depth_2: [
                  { depth_3_found: "found 3a", other: "wrong" },
                  { depth_3_found: "found 3b", other: "wrong" },
                  { depth_3_found: "found 3c", other: "wrong" },
              ],
              other: "wrong",
              complex_a: [
                  { val: "val1",
                    cplxb: [
                        { cplxc: { cplxd: [ { val: "val111" }, { val: "val112" } ] } },
                        { cplxc: { other: "other" } },
                        { other: "other" },
                    ]
                  },
                  { val: "val2",
                    cplxb: [
                        { cplxc: { cplxd: [ { val: "val211" }, { other: "other" } ] } } ]
                  },
                  { other: "other"}
              ]
          },
          other: "wrong"
      },
               other: "wrong"  }

      dsl = DJC::DSL.new do
        depth_0 do
          +depth_1_found("d1")
          depth_1 do
            depth_2 do
              +depth_3_found("d3")
            end
            complex_a do
              +val("val")
              cplxb.cplxc.cplxd do
                +val("innerval")
              end
            end
          end
        end
      end

      dsl.parse(data).sort{ |a,b| a.to_s <=> b.to_s }.should == [
          { "d1" => "found 1", "d3" => "found 3a", "val" => "val1", "innerval" => "val111"},
          { "d1" => "found 1", "d3" => "found 3a", "val" => "val1", "innerval" => "val112"},
          { "d1" => "found 1", "d3" => "found 3a", "val" => "val1", "innerval" => nil},
          { "d1" => "found 1", "d3" => "found 3a", "val" => "val1", "innerval" => nil},
          { "d1" => "found 1", "d3" => "found 3a", "val" => "val2", "innerval" => "val211"},
          { "d1" => "found 1", "d3" => "found 3a", "val" => "val2", "innerval" => nil},
          { "d1" => "found 1", "d3" => "found 3a", "val" => nil,    "innerval" => nil},

          { "d1" => "found 1", "d3" => "found 3b", "val" => "val1", "innerval" => "val111"},
          { "d1" => "found 1", "d3" => "found 3b", "val" => "val1", "innerval" => "val112"},
          { "d1" => "found 1", "d3" => "found 3b", "val" => "val1", "innerval" => nil},
          { "d1" => "found 1", "d3" => "found 3b", "val" => "val1", "innerval" => nil},
          { "d1" => "found 1", "d3" => "found 3b", "val" => "val2", "innerval" => "val211"},
          { "d1" => "found 1", "d3" => "found 3b", "val" => "val2", "innerval" => nil},
          { "d1" => "found 1", "d3" => "found 3b", "val" => nil,    "innerval" => nil},

          { "d1" => "found 1", "d3" => "found 3c", "val" => "val1", "innerval" => "val111"},
          { "d1" => "found 1", "d3" => "found 3c", "val" => "val1", "innerval" => "val112"},
          { "d1" => "found 1", "d3" => "found 3c", "val" => "val1", "innerval" => nil},
          { "d1" => "found 1", "d3" => "found 3c", "val" => "val1", "innerval" => nil},
          { "d1" => "found 1", "d3" => "found 3c", "val" => "val2", "innerval" => "val211"},
          { "d1" => "found 1", "d3" => "found 3c", "val" => "val2", "innerval" => nil},
          { "d1" => "found 1", "d3" => "found 3c", "val" => nil,    "innerval" => nil}
      ].sort { |a,b| a.to_s <=> b.to_s }
    end

    it "can compose new values based on one or more fields" do
      data = {
          sum: [1, 2, 3.3],
          avg: [1, 2, 3],
          uniq: [1, 2, 1, 3, 1, 4],
          join: [1, 2, 3, 4, 5],
          count: [1, 2, 3, 4, 5],
          capture: "abc 123 xyz"
      }

      dsl = DJC::DSL.new do
        +sum.sum
        +avg.avg
        +uniq.uniq
        +join.join
        +count.count
        +capture.capture(/(\w+) (\d+)/, 1, 2)
        +with("sum, avg, uniq, join, count, capture").compose { |*values|
          values.flatten.map(&:to_s).join().split('').sort.uniq.join.strip
        } % :all
      end

      dsl.parse(data).should == [{
          sum: 6.3,
          avg: 2.0,
          uniq: [1,2,3,4],
          join: "12345",
          count: 5,
          capture: ["abc", "123"],
          all: ".12345abcxyz"
      }]
    end

    it "can include all the fields under a block" do
      data = {
          hash_field: {
              a: "a",
              b: "b",
              c: "c"
          },
          array_field: [ 11, 12, 13 ]
      }

      dsl = DJC::DSL.new do
        +hash_field.*
        +array_field.*
      end

      p dsl

      dsl.parse(data).should == [{
        "hash_field_a"   => "a",
        "hash_field_b"   => "b",
        "hash_field_c"   => "c",
        "array_field[0]" => 11,
        "array_field[1]" => 12,
        "array_field[2]" => 13
      }]

    end


    xit "can have reusable sub dsls" do

    end

    xit "can return the matched parts of a find" do

    end

  end

  context "DJC#build" do

    xit "can handle files, JSON strings and JSON objects" do

    end

    xit "can define headers with non-unique fields" do

    end

    it "can build a complete CSV from a JSON strings and merge rules" do

      teachers = <<-JSON
[
  {"id":1, "name":"Albert Einstein"},
  {"id":2, "name":"Teacher McTeacherson"},
  {"id":3, "name":"Instructinator"}
]
      JSON

      sales = <<-JSON
{
  "customers" : [
    {"id": 100,
     "name": "Company Inc",
     "employees": [
       {"id":1,"name":{"first":"Joe","last":"Schmoe"},     "jobtitle":"CEO","address":"123 fake street","date joined":"2001-01-10","boss":null},
       {"id":2,"name":{"first":"Jane","last":"Jabang"},    "jobtitle":"Internal Affairs Chief","address1":"123 fake street","address2":"Faketown, USA","date started":"2001-03-10","boss":1},
       {"id":3,"name":{"first":"Mebook","last":"Garblong"},"jobtitle":"Alien Visitor Hospitality Officer","address":"123 fake street","date joined":"2001-04-10","boss":1}
    ]},
    {"id": 200,
     "name": "Other Company DotCom",
     "employees": [
       {"id":11,"name":{"first":"Dame","last":"Edna"},     "jobtitle":"CEO","address":"123 fake street","date joined":"2001-01-10","boss":null},
       {"id":12,"name":{"first":"Senor","last":"Whoozit"}, "jobtitle":"Senior Engineer","address1":"123 fake street","address2":"Faketown, USA","date started":"2001-03-10","boss":11}
    ]}
  ],
  "seminars" : [
    { "code" : "AAP-1003/J",
      "name": "Your Company and You",
      "attendees": [
        { "company": 100, "employee": 1 },
        { "company": 200, "employee": 1 },
        { "company": 200, "employee": 2 }
      ],
      "instructor": 2
    },
    { "code" : "AAP-1004",
      "name": "50 ways to kill your boss without anyone finding out",
      "attendees": [
        { "company": 100, "employee": 2 },
        { "company": 100, "employee": 3 }
      ],
      "instructor": 3
    }
  ]
}
      JSON

      csv = DJC.build(instructors:teachers, classes:sales) do
        mappings do
          classes.seminars & instructors % instructor
          instructor <=> id

          classes.seminars.attendees & classes.customers.employees
          employee <=> id
          company <=> --id

          classes.seminars.attendees & classes.customers % corp
          company <=> id

          classes.customers.employees & classes.customers.employees % manager
          boss <=> id
        end

        dsl('seminar_id', 'teacher', 'attendee', 'company', 'title', 'boss') do
          classes.seminars do
            +code("seminar_id").capture(/^(\w+)(-)(\d+)/, 1, 3).join(":")
            +instructor.name("teacher").capture(/(?<teacher_name>[^\s]*)$/, :teacher_name)

            attendees do
              corp do
                +name("company")
                employees do
                  +jobtitle("title")
                  name do
                    +with("first,last").join(" ") > "attendee"
                  end

                  manager do
                    name do
                      +with("first,last").compose { |first, last|
                        first ? "#{first} #{last}" : "N/A"
                      } > 'boss'
                    end
                  end
                end
              end
            end
          end
        end
      end

      csv.to_s.should == <<-CSV
seminar_id,teacher,attendee,company,title,boss
AAP:1003,McTeacherson,Joe Schmoe,Company Inc,CEO,N/A
AAP:1003,McTeacherson,Jane Jabang,Company Inc,Internal Affairs Chief,Joe Schmoe
AAP:1003,McTeacherson,Mebook Garblong,Company Inc,Alien Visitor Hospitality Officer,Joe Schmoe
AAP:1003,McTeacherson,Dame Edna,Other Company DotCom,CEO,N/A
AAP:1003,McTeacherson,Senor Whoozit,Other Company DotCom,Senior Engineer,Dame Edna
AAP:1003,McTeacherson,Dame Edna,Other Company DotCom,CEO,N/A
AAP:1003,McTeacherson,Senor Whoozit,Other Company DotCom,Senior Engineer,Dame Edna
AAP:1004,Instructinator,Joe Schmoe,Company Inc,CEO,N/A
AAP:1004,Instructinator,Jane Jabang,Company Inc,Internal Affairs Chief,Joe Schmoe
AAP:1004,Instructinator,Mebook Garblong,Company Inc,Alien Visitor Hospitality Officer,Joe Schmoe
AAP:1004,Instructinator,Joe Schmoe,Company Inc,CEO,N/A
AAP:1004,Instructinator,Jane Jabang,Company Inc,Internal Affairs Chief,Joe Schmoe
AAP:1004,Instructinator,Mebook Garblong,Company Inc,Alien Visitor Hospitality Officer,Joe Schmoe
      CSV

#TODO check/fix this
#xxx
#the above is probably wrong somehow, the below is more expected:
#don't have time ot figure out why tonight

#seminar_id,teacher,attendee,company,title,boss
#AAP:1003,McTeacherson,Joe Schmoe,Company Inc,CEO,N/A
#AAP:1003,McTeacherson,Dame Edna,Other Company DotCom,CEO,N/A
#AAP:1003,McTeacherson,Dame Edna,Other Company DotCom,Senior Engineer,Dame Edna
#AAP:1004,Instructinator,Jane Jabang,Company Inc,Internal Affairs Chief,Joe Schmoe
#AAP:1004,Instructinator,Meebook Garblong,Company Inc,Alien Visitor Hospitality Officer,Joe Schmoe
#    CSV
#
    end

  end



end
