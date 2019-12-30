#!/usr/bin/ruby

require 'bitso/apiv3'
require 'bigdecimal'

class CurrencyLayer
  def initialize(api_key)
    @api_key = api_key
    @conn = Net::HTTP.new("apilayer.net", 443)
    @conn.use_ssl = true
  end

  def get_quote
    req = Net::HTTP::Get.new("/api/live?access_key=#{@api_key}&currencies=ARS&source=MXN")
    resp = @conn.request(req)
    begin
      j = JSON.parse(resp.body)
      if j["success"] == true
        return BigDecimal(j["quotes"]["MXNARS"], 5)
      end
    rescue JSON::ParserError
    end
    return nil
  end
end

def getBalances
  balance = $bitso.balance

  h = Hash.new
  balance["balances"].each do |b|
    h["ars"] = b if b["currency"] == "ars"
    h["btc"] = b if b["currency"] == "btc"
  end

  return h
end

def getBTCMXN
  ticker = $bitso.ticker
  ticker.each do |t|
    return BigDecimal(t["last"]) if t["book"] == "btc_mxn"
  end
  return nil
end

def calculateSpreads
  mxn_btc = getBTCMXN
  ars_mxn = $cl.get_quote
  balances = getBalances
  ars_balance = BigDecimal(balances["ars"]["total"])
  btc_in_ars = BigDecimal(balances["btc"]["total"]).mult(mxn_btc, 8).mult(ars_mxn, 8)
  total_balance_in_ars = ars_balance.add(btc_in_ars, 8)
  btc_percentage = btc_in_ars.div(total_balance_in_ars, 8)
  puts "BTC is at #{btc_percentage.mult(BigDecimal("100"), 2).to_s("F")}%"
  puts "ARS is at #{BigDecimal("100").sub(btc_percentage.mult(BigDecimal("100"), 2), 2).to_s("F")}%"

  h = Hash.new
  h["bid_spread"] = $max_spread
  h["ask_spread"] = $max_spread
  m = ($min_spread-$max_spread)/BigDecimal("0.5")
  b = $min_spread-($min_spread-$max_spread)/BigDecimal("0.5")
  if (btc_percentage > BigDecimal("0.5"))
    puts "Reducing ask spread"
    h["ask_spread"] = m*btc_percentage+b
  elsif (btc_percentage < BigDecimal("0.5"))
    puts "Reducing bids spread"
    h["bid_spread"] = m*(BigDecimal("1")-btc_percentage)+b
  end
  puts "Setting bid spread to #{(h["bid_spread"]*BigDecimal("100")).to_s("F")} %"
  puts "Setting ask spread to #{(h["ask_spread"]*BigDecimal("100")).to_s("F")} %"
  return h
end

$min_spread = BigDecimal("0.01")
$max_spread = BigDecimal("0.05")


# read -p "Enter Bitso API key: " -s BITSO_API_KEY && export BITSO_API_KEY && echo && read -p "Enter Bitso API secret: " -s BITSO_API_SECRET && export BITSO_API_SECRET && echo && read -p "Enter CL API key: " -s CL_API && export CL_API && echo
$bitso = Bitso::APIv3::Client.new(ENV["BITSO_API_KEY"], ENV["BITSO_API_SECRET"])
$cl = CurrencyLayer.new(ENV["CL_API"])

while true
  calculateSpreads

  Process.exit
  ob = rest_api.orderbook(:book => "btc_mxn")

  puts "asks"
  ob.asks.each do |a|
    ars_p = BigDecimal(a["price"]).mult(quote, 5).mult(BigDecimal("1").add(spread, 5), 5)
    puts "Orig: #{a["price"]} vs new: #{ars_p.to_s("F")}"
  end

  puts "bids"
  ob.bids.each do |b|
    ars_p = BigDecimal(b["price"]).mult(quote, 5).mult(BigDecimal("1").sub(spread, 5), 5)
    puts "Orig: #{b["price"]} vs new: #{ars_p.to_s("F")}"
  end
end
