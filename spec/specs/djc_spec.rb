require '../spec_helper'

describe DJC do

  describe "DJC#merge" do

    xit "can merge two hashes based on smart rules" do

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

  it "can be a DSL that doesn't suck" do
    json = <<-JSON
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
       {"id":12,"name":{"first":"Senor","last":"Whoozit"}, "jobtitle":"Senior Engineer","address1":"123 fake street","address2":"Faketown, USA","date started":"2001-03-10","boss":1}
    ]}
  ]
}
    JSON

    dsl = DJC::DSL.new do
      customers do
        +name("company_name")
        employees do
          +id
          name do
            +first
            +last
          end
          +"date joined"
        end
      end
    end

#    puts dsl.to_s

    parsed = dsl.parse(JSON.parse(json))

    ap parsed

    parsed.should == [
        {"company_name" => "Company Inc",          "employees_id" => "1", "employees_name_first" => "Joe",    "employees_name_last" => "Schmoe",   "date joined" => "2001-01-10"},
        {"company_name" => "Company Inc",          "employees_id" => "2", "employees_name_first" => "Jane",   "employees_name_last" => "Jabang",   "date joined" => "2001-02-10"},
        {"company_name" => "Company Inc",          "employees_id" => "3", "employees_name_first" => "Mebook", "employees_name_last" => "Garblong", "date joined" => "2001-04-10"},
        {"company_name" => "Other Company DotCom", "employees_id" => "1", "employees_name_first" => "Dame",   "employees_name_last" => "Edna",     "date joined" => "2001-01-10"},
        {"company_name" => "Other Company DotCom", "employees_id" => "2", "employees_name_first" => "Senor",  "employees_name_last" => "Whoozit",  "date joined" => "2001-03-10"}
    ]


  end

  it "can build a complete CSV from a JSON structure" do

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
      mappings do
        classes.seminars & instructors % instructor
        instructor <=> id

        classes.seminars.attendees & classes.customers.employees
        employee <=> id
        company <=> --id

        classes.seminars.attendees.company & classes.customers
        company <=> id

        classes.customers.employees & classes.customers.employees % boss
        boss <=> id
      end

      rules do
        classes.seminars do
                   "seminar_id"         < code[/.*?-(\d+).*/]
                   "teacher_first_name" < instructor.name[/(\w+) \w+/]
                   "teacher_last_name"  < "instructor.name"[/\w+ (\w+)/]

          attendees do
            name { "attendee"           < "first,last".join(' ') }
                   "company_name"       < company.name
                   "title"              < "jobtitle"
                   "boss"               < "boss.name.first,last".do { |first, last| "#{last}, #{first}" }
          end
        end
      end
    end

    pp csv

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
