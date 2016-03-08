require 'rubygems'
require 'bundler/setup'

require 'mechanize'
require 'byebug'

class DPS

  attr_reader :agent

  BASE_URL = 'https://data.kpu.go.id/dps.php'
  GENDERS  = { 'laki-laki' => 'm', 'perempuan' => 'f' }

  def initialize
    @agent = Mechanize.new
  end

  def provinces
    @provinces ||= begin
      root  = fetch BASE_URL
      nodes = root.search('.formcontainer > .form option')

      NodeMapper.new(nodes).map
    end
  end

  def province_ids
    provinces.keys
  end

  def cities(province_id)
    cities = fetch Url.select(0, province_id)
    nodes  = cities.search('#subcat_0 select option')

    NodeMapper.new(nodes).map
  end

  def city_ids(province_id)
    cities(province_id).keys
  end

  def districts(province_id, city_id)
    districts = fetch Url.select(province_id, city_id)
    nodes     = districts.search("#subcat_#{province_id} select option")

    NodeMapper.new(nodes).map
  end

  def district_ids(province_id, city_id)
    districts(province_id, city_id).keys
  end

  def areas(city_id, district_id)
    areas = fetch Url.select(city_id, district_id)
    nodes = areas.search("#subcat_#{city_id} select option")

    NodeMapper.new(nodes).map
  end

  def area_ids(city_id, district_id)
    areas(city_id, district_id).keys
  end

  def tpses(district_id, area_id)
    tpses = fetch Url.select(district_id, area_id)
    nodes = tpses.search('#daftartps select option')

    NodeMapper.new(nodes).map
  end

  def tps_ids(district_id, area_id)
    tpses(district_id, area_id).keys
  end

  def voters(district_id, area_id, tps_num)
    voters = fetch Url.filter(district_id, area_id, tps_num)
    nodes  = voters.search('#daftartps tr')

    NodeMapper.new(nodes).voters
  end

  class Url

    attr_reader :grandparent, :parent, :tps_num

    def self.select(grandparent, parent)
      new(grandparent, parent).select
    end

    def self.filter(grandparent, parent, tps_num)
      new(grandparent, parent, tps_num).filter
    end

    def initialize(grandparent_id, parent_id, tps_num = nil)
      @grandparent = grandparent_id
      @parent      = parent_id
      @tps_num     = tps_num
    end

    def filter
      "#{base}&cmd=Filter&column=filterTPS_new&filter=#{tps_num}"
    end

    def select
      "#{base}&cmd=select"
    end

    def base
      "#{BASE_URL}?grandparent=#{grandparent}&parent=#{parent}"
    end

  end

  class NodeMapper

    attr_reader :nodes

    def initialize(nodes)
      @nodes = nodes
    end

    def map
      nodes.inject({}) do |result, node|
        next result if node['value'].empty?
        result.merge!(node['value'].strip => node.children.first.text.strip.downcase)
      end
    end

    def voters
      nodes.inject([]) do |result, voter|
        record = voter.children.search('td')
        next result unless record.count == 7

        name   = record[2].text.strip.downcase.tr('@', '')
        gender = record[4].text.strip.downcase

        result << name + '@' + GENDERS[gender]
      end
    end

  end

  def fetch(url)
    sleep 0.1
    agent.get(url)
  end

  def start
    log   = File.open('log/fetch.log', 'a+')
    names = File.open('data/names.pair', 'a+')

    i = 0

    provinces.to_a.shuffle.reverse_each do |province_id, province_name|
      cities(province_id).to_a.shuffle.reverse_each do |city_id, city_name|
        districts(province_id, city_id).to_a.shuffle.reverse_each do |district_id, district_name|
          areas(city_id, district_id).to_a.shuffle.reverse_each do |area_id, area_name|
            tps_ids(district_id, area_id).to_a.shuffle.reverse_each do |tps_num|
              voters = voters(district_id, area_id, tps_num)
              names.write voters.join("\n")
              names.write "\n"
              names.flush

              i += voters.count

              message = [[province_id, province_name], [city_id, city_name], [district_id, district_name], [area_id, area_name], [tps_num]].map { |e| e.reverse.join(': ') }.join(' '), [voters.count, i].join(' -> ')

              puts message

              log.write message
              log.write "\n"
              log.flush
            end
          end
        end
        sleep 2
      end
      sleep 2
    end

    names.close
  end

end

DPS.new.start
