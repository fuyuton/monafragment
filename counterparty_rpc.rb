require 'json'
require "uri"
require "net/http"
require_relative  'monaparty'
require_relative '../../floor'

class Http_Client
  def initialize(url)
    @url = URI(url)

    @https = Net::HTTP.new(@url.host, @url.port);
    @https.use_ssl = true

  end

  def post(json)
    @request = Net::HTTP::Post.new(@url)
    @request["Content-Type"] = "application/json"
    @request.body = json
    response = @https.request(@request)
    JSON.parse(response.read_body)
  end
end

class Counterparty_RPC
  def initialize(conf, key_conf)
    network = conf['network']
    url = conf['api']
    is_testnet = conf['is_testnet']
    @source = conf['src_address']
    @secret = conf['secret']
    @fee = conf['fee_per_satoshi']
    @asset = conf['coin_name'].upcase

    if conf['address_name'] != key_conf['name']
      puts "invalid secret key"
      exit
    end
    @secret = key_conf['priv_key']

    @api = Http_Client.new(url)
    Bitcoin.network = is_testnet ? "#{network}_testnet".to_sym : network.to_sym  
    #p url
    @mp = Monaparty.new(network, url, is_testnet)
  end

  def valid_address?(address)
    @mp.valid_address?(address)
  end

  def balance(address)
    @mp.get_balance_basecoin(address)
  end

  def token_balance(address)
    @mp.get_token_balance(address)
  end

  def getrawtransaction(tx_hash, verbose=false, skip_missing=false)
    @mp.get_raw_transaction(tx_hash, verbose, skip_missing)
  end
  
  def send(to, qty)
    if @secret.nil?
      puts "secret is nil"
      exit
    end
    unsigned_tx = @mp.create_unsigned_tx(@source, to, @asset, qty, @fee)
    signed_tx = @mp.sign(unsigned_tx, @secret)
    tx_id = @mp.broadcast(signed_tx)
  end

  def bonus_send(to, qty, base_qty)
    if @secret.nil?
      puts "secret is nil"
      exit
    end
    unsigned_tx = @mp.create_unsigned_tx(@source, to, @asset, qty, @fee, false, fmul(base_qty,100000000).to_i)
    signed_tx = @mp.sign(unsigned_tx, @secret)
    tx_id = @mp.broadcast(signed_tx)
  end

end

if __FILE__ == $0
  network = "monacoin"
  is_testnet = true

  #testnet
  #url = "https://testnet-monapa.electrum-mona.org/_t_api"
  url = "https://wallet-testnet.monaparty.me/_t_api"
  src_address = "mr8q13FpJGQeYcCW9zCtZRF8sb56ny6kqp"
  dest_address = "n3Yj7xsns1WTjkSBiQBh94aRrvBTWyJX72"
  secret = "cS7izkDfiXbiZXYTsEgYweCNPiRu3D6XDFd2q5rggnvkD2QDGjZm"

  asset = "XMP"
  qty = 1
  fee_satoshi = 110

  puts "URL: #{url}"
  conf = {
    'network'=> network,
    'url'=> url,
    'is_testnet'=> is_testnet,
    'secret'=> secret,
    'src_address'=> src_address,
    'fee_per_satoshi'=> fee_satoshi,
    'asset'=> asset,
  }
  mp = Counterparty_RPC.new(conf)
  puts "valid? #{mp.valid_address?(src_address)}"

  puts "get mona balance"
  res = mp.balance(src_address)
  puts res
  mona_amount = res
  #if mona_amount < 0.01
  #  puts "insufficient mona"
  #  exit
  #end

  puts "get token balance"
  xmp_amount = mp.token_balance(src_address)
  puts xmp_amount
  if xmp_amount < 1
    puts "insufficient mona"
    exit
  end

  #puts "create unsigned_tx"
  #unsigned_tx = mp.create_unsigned_tx(src_address, dest_address, asset, qty, false, 372400, fee_satoshi) #send dust
  #qty = 1 #1monaで3333回くらい送れる。1回3XMP配るとして、1万XMP
  #unsigned_tx = mp.create_unsigned_tx(src_address, dest_address, asset, qty, false, 100000000, fee_satoshi) #send dust
  #puts 'send'
  #txid = mp.send(dest_address, qty) #, true, 0, fee_satoshi) #token only
  #puts "txid: #{txid}"

  puts 'bonus send'
  mona_qyt = 0.0003
  txid = mp.bonus_send(dest_address, qty, mona_qty)
  puts "txid: #{txid}"


end
