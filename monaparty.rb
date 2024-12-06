require 'json'
require "uri"
require "net/http"
require 'bitcoin'
require_relative '../../floor'

class Http_Client
  def initialize(url)
    @url = URI url

    @https = Net::HTTP.new(@url.host, @url.port);
    @https.use_ssl = true

    @request = Net::HTTP::Post.new(@url)
    @request["Content-Type"] = "application/json"
  end

  def post(json)
    @request.body = json
    response = @https.request(@request)
    begin
      JSON.parse(response.read_body)
    rescue => e
      p e
      p e.message
      raise
    end

  end
end

class Monaparty
  def initialize(network, url, is_testnet)
    @api = Http_Client.new(url)

    #ネットワークの指定
    Bitcoin.network = is_testnet ? "#{network}_testnet".to_sym : network.to_sym
  end
  
  def valid_address?(address)
    Bitcoin.valid_address?(address)
  end

  #getrawtransaction
  def get_raw_transaction(tx_hash, verbose=false, skip_missing=false)
    json = create_proxy_json("getrawtransaction", {"tx_hash": "#{tx_hash}", "verbose": verbose, "skip_missing": skip_missing })
    res = @api.post(json)
    #puts "#{__method__}: #{res}"
    verbose ? res['result']['hex'] : res['result']
  end

  #MONAの残高を見る
  def get_balance_basecoin(address)
    json = create_json("get_chain_address_info", {"addresses":["#{address}"],"with_uxtos":"True","with_last_txn_hashes":"4"})
    res = @api.post(json)
    #{"id"=>0, "result"=>[{"last_txns"=>[], "uxtos"=>[], "addr"=>"MQsvA3C7J9dZJSxAURYEq4MuZttD2JJ9Xm", "block_height"=>2124921, "info"=>{"addrStr"=>"MQsvA3C7J9dZJSxAURYEq4MuZttD2JJ9Xm", "balance"=>0, "unconfirmedBalanceSat"=>"0", "unconfirmedBalance"=>"0", "balanceSat"=>"0"}}], "jsonrpc"=>"2.0"}
    balance = ''
    res['result'].each {|elem|
      info = elem['info']
      balance = info['balance'] if info['addrStr'] == address
    }
    balance
  end

  #アセット(トークン)の残高を見る
  def get_token_balance(address)
    json = create_json("get_normalized_balances", {"addresses":["#{address}"]})
    res = @api.post(json)
    #{"id"=>0, "result"=>[], "jsonrpc"=>"2.0"}
    #{"id"=>0, "result"=>[{"normalized_quantity"=>10.0, "quantity"=>1000000000, "asset"=>"XMP", "address"=>"MQsvA3C7J9dZJSxAURYEq4MuZttD2JJ9Xm", "asset_longname"=>nil, "owner"=>false}], "jsonrpc"=>"2.0"}
    balance = ''
    if !res['result'].empty?
      res['result'].each {|elem|
        balance = elem['normalized_quantity'] if elem['address'] == address
      }
    end
    balance
  end

  def create_unsigned_tx(src, dest, asset, qty, fee=110, is_enhanced_send=true, dust_qty=0)
      #https://counterparty.io/docs/api/#advanced-create_-parameters
      #p "fee: #{fee}"
      json = create_proxy_json(
      "create_send",
      {
        "source": src,
        "destination": dest,
        "asset": asset,
        "quantity": fmul(qty, 100000000).to_i,
        "fee_per_kb": fmul(fee, 1024).to_i,
        "allow_unconfirmed_inputs": false,
        "disable_utxo_locks": true,
        "encoding": "auto",
        "extended_tx_info": true,
        "use_enhanced_send": is_enhanced_send,
        "regular_dust_size": dust_qty,
      }
    )
    #puts json
    res = @api.post(json)
    #puts res

    if res.has_key?('result') && res['result'].has_key?('tx_hex')
      unsigned_tx = res['result']['tx_hex']
      #puts "\nunsigned_tx: #{unsigned_tx}"
    else
      puts "#{__method__} Error:\n"
      puts "#{res}\n"
      exit
    end
    unsigned_tx
  end

  def sign(unsigned_tx, secret)
    #鍵の準備
    key = Bitcoin::Key.from_base58 secret
    pubkey = [key.pub].pack('H*')

    #トランザクションを作る
    #成功バージョン(ただしdust monaも送られる)
    tx = Bitcoin::Protocol::Tx.new([unsigned_tx].pack("H*"))
    prev_hash = tx.in[0].prev_out.reverse_hth
    #puts "prev_hash: #{prev_hash}"
    prev_tx_hex = [get_raw_transaction(prev_hash)].pack('H*')
    prev_tx = Bitcoin::Protocol::Tx.new(prev_tx_hex)
    subscript = tx.signature_hash_for_input(0, prev_tx)

    #puts "subscript: #{subscript.unpack('H*')[0]}"

    #署名する
    signed_tx = Bitcoin.sign_data(Bitcoin.open_key(key.priv), subscript)
    tx.in[0].script_sig = Bitcoin::Script.to_signature_pubkey_script signed_tx, pubkey
    signed_tx_hex = tx.to_payload.unpack('H*')[0]
  end

  def broadcast(signed_tx_hex)
    json = create_json("broadcast_tx", {signed_tx_hex: signed_tx_hex})
    res = @api.post(json)

    if res.has_key?('result')
      txid = res['result']
    else
      puts "#{__method__} Error:\n"
      puts "#{res}\n"
      if res['error']['data']['type'] == "Exception"
        puts res['error']['data']['args']
      end
        
      exit
    end
    txid
  end
  
  
  private

  def create_json(method, params)
    %Q{{
      "jsonrpc": "2.0",
      "id": #{Time.now.to_i},
      "method": "#{method}",
      "params": #{params.to_json}
    }}
  end

  def create_proxy_json(method, params)
    %Q{{
        "jsonrpc": "2.0",
        "id": #{Time.now.to_i},
        "method":
        "proxy_to_counterpartyd",
        "params":
        {
          "method": "#{method}",
          "params": #{params.to_json}
        }
    }}
  end

end


if __FILE__ == $0
  network = "monacoin" 
  is_testnet = true
  
  if !is_testnet
    #url = ("https://counterblock.api.monaparty.me/")
    #url = ("https://wallet.monaparty.me/_api")
    url = ("https://monapa.electrum-mona.org/_api")
    secret = ""
    src_address = "" 
    dest_address = "" 
  else
    #testnet
    url = ("https://testnet-monapa.electrum-mona.org/_t_api")
    #url = ("https://wallet-testnet.monaparty.me/_t_api")
    src_address = "mr8q13FpJGQeYcCW9zCtZRF8sb56ny6kqp"
    dest_address = "n3Yj7xsns1WTjkSBiQBh94aRrvBTWyJX72"
    secret = "cS7izkDfiXbiZXYTsEgYweCNPiRu3D6XDFd2q5rggnvkD2QDGjZm"
  end

  puts "URL: #{url}"
  mp = Monaparty.new(network, url, is_testnet)

  puts "valid? #{mp.valid_address?(src_address)}"


  asset = "XMP"
  qty = 1
  fee_satoshi = 110
  #fee_satoshi = 1100


  mona_amount = mp.get_balance_basecoin(src_address)
  puts "mona balance: #{mona_amount}"
  if mona_amount < 0.0004
    puts "insufficient mona"
    exit
  end
  if mona_amount < 0.01
    puts "insufficient mona"
    exit
  end

  xmp_amount = mp.get_token_balance(src_address)
  puts "token balance: #{xmp_amount}"
  if xmp_amount < 1
    puts "insufficient xmp"
    exit
  end

  puts "create unsigned_tx"
  #unsigned_tx = mp.create_unsigned_tx(src_address, dest_address, asset, qty, fee_satoshi, false, 372400) #send dust
  #qty = 10000 #1monaで3333回くらい送れる。1回3XMP配るとして、1万XMP
  #unsigned_tx = mp.create_unsigned_tx(src_address, dest_address, asset, qty, fee_satoshi, false, 100000000) #send dust
  unsigned_tx = mp.create_unsigned_tx(src_address, dest_address, asset, qty, fee_satoshi, true, 0) #token only
  puts "unsigned_tx: #{unsigned_tx}"

  puts "create signed_tx"
  signed_tx_hex = mp.sign(unsigned_tx, secret)
  puts "signed_tx_hex: #{signed_tx_hex}"

  puts "send signed_tx"
  txid = mp.broadcast(signed_tx_hex)
  puts "txid: #{txid}"


end
