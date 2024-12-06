require_relative 'api/btc_rpc'
require_relative 'api/eth_rpc'
#require_relative 'api/nem_rpc'
require_relative 'api/counterparty_rpc'

class RPC_API
  def initialize(conf, keyconf=nil)
    series = conf['series']
    case series
    when 'btc'
      @rpc = Btc_rpc.new(conf)
    when 'eth'
      @rpc = Eth_rpc.new(conf)
    when 'nem'
      #@rpc = Nem_rpc.new(conf)
    when 'counterparty'
      @rpc = Counterparty_RPC.new(conf, keyconf)
    end
  end

  def valid_address?(addr)
    @rpc.valid_address?(addr)
  end

  def send(to, vol)
    @rpc.send(to, vol)
  end

  def send_many(send_list)
    @rpc.send_many(send_list)
  end

  def balance(address='')
    @rpc.balance(address)
  end

  def get_transaction(txid)
    @rpc.get_transaction(txid)
  end

  #counterparty 拡張

  def token_balance(address)
    @rpc.token_balance(address)
  end

  def getrawtransaction(tx_hash, verbose=false, skip_missing=false)
    @rpc.getrawtransaction(tx_hash, verbose, skip_missing)
  end

  def bonus_send(to, qty, base_qty)
    @rpc.bonus_send(to, qty, base_qty)
  end
end
