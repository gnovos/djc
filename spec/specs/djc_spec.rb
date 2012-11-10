require '../spec_helper'

describe DJC do

  describe String do
    it "can convery to literal using unary ~ operator" do
      str = ~"str"
      str.should == "~str"
    end

    it "can parse itself into path tokens" do
      paths = [
          "a.b1|b2|~lit.c[0,0-0,0..0,0...0,0+]./de/.f&g.{{h}}.j,k,l./(m).|&\\{\\[/.n.!o.{{p.q}}.r&s|t,u"
      ]
      paths.map(&:tokenize).map(&:to_s).should == [
          DJC::Token.new(:root,
              DJC::Token.new(:path, :a),
              DJC::Token.new(:any, DJC::Token.new(:path, "b1"), DJC::Token.new(:path, "b2"), DJC::Token.new(:literal, "lit")),
              DJC::Token.new(:path, "c", :indexes => [0, 0..0, 0..0, 0...0, 0..-1]),
              DJC::Token.new(:regex, /de/),
              DJC::Token.new(:all, DJC::Token.new(:path, "f"), DJC::Token.new(:path, "g")),
              DJC::Token.new(:lookup, DJC::Token.new(:path, "h")),
              DJC::Token.new(:each, DJC::Token.new(:path, "j"), DJC::Token.new(:path, "k"), DJC::Token.new(:path, "l")),
              DJC::Token.new(:regex, /(m).|&\{\[/),
              DJC::Token.new(:path, "n"),
              DJC::Token.new(:inverse, DJC::Token.new(:path, "o")),
              DJC::Token.new(:lookup, DJC::Token.new(:root, DJC::Token.new(:path, "p"), DJC::Token.new(:path, "q"))),
              DJC::Token.new(:each, DJC::Token.new(:all, DJC::Token.new(:path, "r"),
                                                   DJC::Token.new(:any, DJC::Token.new(:path, "s"), DJC::Token.new(:path, "t"))),
                                                   DJC::Token.new(:path, "u")),
          ).to_s
      ]

    end
  end

  describe DJC::Token do
    it("can walk a tree") do
      obj = {
          a: [ "b", "c", "d"],
          b: [ { c: { d: "foundA" } }, { c: { d: "foundB" } } ],
          c: [ [[{d:'f0'},{d:'f1'}], [{d:'f2'},{d:'f3'}]], [[{d:'f4'},{d:'f5'}], [{d:'f6'},{d:'f7'}]] ],
          d: [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 ],
          e: nil,
          f: nil,
          g: "found by any",
          h: "not any",
          foo_a: "regex0",
          foo_b: "regex1",
          foo_ccccc: "regex2",
          i: { j: [ {k:"found0"}, {k:"found1"} ] },
          l: { m: [ {n:"found2"}, {n:"found3"} ] },
          lookval: { o: [ "i.j.k", "l.m.n" ] }
      }

      DJC::Token.new(:path, "a").walk(obj).should == obj[:a]
      DJC::Token.new(:root,
                     DJC::Token.new(:path, :b),
                     DJC::Token.new(:path, :c),
                     DJC::Token.new(:path, :d)).walk(obj).should == [ "foundA", "foundB"]
      DJC::Token.new(:root,
                     DJC::Token.new(:path, :c),
                     DJC::Token.new(:path, :d)).walk(obj).should == [ 'f0','f1','f2','f3','f4','f5','f6', 'f7' ]
      DJC::Token.new(:root,
                     DJC::Token.new(:path, :c)).walk(obj).should == [ {d:'f0'}, {d:'f1'}, {d:'f2'}, {d:'f3'}, {d:'f4'}, {d:'f5'}, {d:'f6'}, {d:'f7'} ]
      DJC::Token.new(:path, :d, indexes: [1, 2..4, 5...7, 8..-1]).walk(obj).should == [ 1, 2, 3, 4, 5, 6, 8, 9 ]
      DJC::Token.new(:literal, :foo).walk(obj).should == "foo"
      DJC::Token.new(:any,
                     DJC::Token.new(:path, :e),
                     DJC::Token.new(:path, :f),
                     DJC::Token.new(:path, :g),
                     DJC::Token.new(:path, :h)).walk(obj).should == "found by any"
      DJC::Token.new(:each,
                     DJC::Token.new(:path, :e),
                     DJC::Token.new(:path, :f),
                     DJC::Token.new(:path, :g),
                     DJC::Token.new(:path, :h)).walk(obj).should == [nil, nil, "found by any", "not any"]
      DJC::Token.new(:all,
                     DJC::Token.new(:path, :e),
                     DJC::Token.new(:path, :f),
                     DJC::Token.new(:path, :g),
                     DJC::Token.new(:path, :h)).walk(obj).should == nil
      DJC::Token.new(:all,
                     DJC::Token.new(:path, :g),
                     DJC::Token.new(:path, :h)).walk(obj).should == [ "found by any", "not any" ]
      DJC::Token.new(:regex, /foo_.*/).walk(obj).should == [ "regex0", "regex1", "regex2" ]
      DJC::Token.new(:lookup, DJC::Token.new(:root, DJC::Token.new(:path, :lookval), DJC::Token.new(:path, :o))).walk(obj).should == [ "found0", "found1", "found2", "found3" ]

      #xxx inverse

    end
  end

  describe "DJC#merge" do

    it "can merge two hashes based on smart rules" do

      employees = [
          { company: 0, employees: [ { empid: 0, name: "Joe" }, { empid: 1, name: "Sally" } ] },
          { company: 1, employees: [ { empid: 0, name: "Wong"}, { empid: 1, name: "Wright"} ] }
      ]
      people = { people: [ { employee_id: 0, company_id: 0 }, { employee_id: 1, company_id: 0 }] }

      mapped = DJC::Mapper.map(a:people, b:employees) do
        merge 'a.people.*' < 'b.employees.*'
        where 'employee_id' == 'empid',
              'company_id' == '^.company'

      end

      mapped.should == {
        a: { people: [ { employee_id: 0, company_id: 0, empid: 0, name: "Joe"   },
                       { employee_id: 1, company_id: 0, empid: 1, name: "Sally" }] },
        b: [ { company: 0, employees: [ { empid: 0, name: "Joe" }, { empid: 1, name: "Sally" } ] },
             { company: 1, employees: [ { empid: 0, name: "Wong"}, { empid: 1, name: "Wright"} ] } ]
      }

    end

  end

  describe Array do

    it "can select the first block that return non-nil" do

      count = 0
      [1,2,3,4,5].return_first { |i| count += 1; i == 3 ? "found" : nil }.should == "found"
      count.should == 3

    end

  end

  xit "can build a complete CSV from a JSON structure" do

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
       {"id":1,"name":{"first":"Dame","last":"Edna"},     "jobtitle":"CEO","address":"123 fake street","date joined":"2001-01-10","boss":null},
       {"id":2,"name":{"first":"Senor","last":"Whoozit"}, "jobtitle":"Senior Engineer","address1":"123 fake street","address2":"Faketown, USA","date started":"2001-03-10","boss":1}
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
      #map("classes.seminars.instructor")
      #  .to("instructors")
      #  .on("instructors.id")
      #
      #map("classes.seminars.attendees")
      #  .to("classes.customers.employees")
      #  .where("classes.seminars.attendees.company")
      #  .equals("classes.customers.id")
      #  .and("classes.seminars.attendees.employee")
      #  .equals("classes.customers.employees.id")

#      map "classes.seminars.attendees.company" => "customers.id"

      rule("attendees", "classes.seminars.attendees.%company<classes.customers.id>%")
      #
      #cols["seminar_id"] = with("classes.seminars.code").match(/.*?-(\d+).*/)
      #cols["teacher"] = with("<classes.seminars.instructor=instructors.*.id>.name").match(/.*?-(\d+).*/)
      #cols["attendee"] = with("classes.seminars.attendees.*.employee<classes.customers.id>.name").match(/.*?-(\d+).*/)

    end

    #puts csv

    csv.should == <<-CSV
seminar_id,teacher,attendee,company,title,boss
1003,McTeacherson,Joe Schmoe,Company Inc,CEO,N/A
1003,McTeacherson,Dame Edna,Other Company DotCom,CEO,N/A
1003,McTeacherson,Dame Edna,Other Company DotCom,Senior Engineer,Dame Edna
1004,Instructinator,Jane Jabang,Company Inc,Internal Affairs Chief,Joe Schmoe
1004,Instructinator,Meebook Garblong,Company Inc,Alien Visitor Hospitality Officer,Joe Schmoe
    CSV

  end


end


#path.by.dots
#| means first non null
#, means gather all into array
#& means merge (somehow?)
#!means inverse? (Often create array)
#* means all of previous
#[array access]
#> all sep by ,
#> 0, 0-0, 0..0, 0...0, 0+
#> no index means all
#{{lookup - val becomes key}}
#/regexp - match is key(s)/
#
#? Join where matching
#
#merge "customer"
#to "clients.company.employee"
#where
#("customer.name.first", c.n.l).join(" ") =
#    "cce.name"
#and "
#  or "c.id" = "c.c.e.e_id"
