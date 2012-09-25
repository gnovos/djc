require 'json'
require 'csv'

module DJC

  def self.map(json = nil, to = nil, &block)
    json = JSON.parse(json) if json.is_a?(String)

    if (block)
      block.call(json)
    end

    out = CSV.generate do |csv|

    end
    out
  end


end