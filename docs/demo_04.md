# In-flight exits

The following demo is a mix of commands executed in IEx (Elixir's) REPL (see README.md for instructions) and shell.

Run a developer's Child chain server, Watcher, and start IEx REPL with code and config loaded, as described in README.md instructions.

```elixir

### PREPARATIONS

# we're going to be using the exthereum's client to geth's JSON RPC
{:ok, _} = Application.ensure_all_started(:ethereumex)

alias OMG.{API, Eth}
alias OMG.API.Crypto
alias OMG.API.DevCrypto
alias OMG.API.State.Transaction
alias OMG.API.TestHelper
alias OMG.RPC.Web.Encoding

alice = TestHelper.generate_entity()
bob = TestHelper.generate_entity()
eth = Crypto.zero_address()

{:ok, alice_enc} = Eth.DevHelpers.import_unlock_fund(alice)

### START DEMO HERE

# sends a deposit transaction _to Ethereum_
# we need to uncover the height at which the deposit went through on the root chain
# to do this, look in the logs inside the receipt printed just above
deposit_blknum = DepositHelper.deposit_to_child_chain(alice.addr, 10)

# create and prepare transaction for signing
tx =
  Transaction.new([{deposit_blknum, 0, 0}], [{bob.addr, eth, 7}, {alice.addr, eth, 3}]) |>
  DevCrypto.sign([alice.priv, <<>>]) |>
  Transaction.Signed.encode() |>
  Encoding.to_hex()

# submits a transaction to the child chain
# this only will work after the deposit has been "consumed" by the child chain, be patient (~15sec)
# use the hex-encoded tx bytes and `transaction.submit` Http-RPC method described in README.md for child chain server
%{"data" => %{"blknum" => child_tx_block_number, "tx_index" => tx_index}} =
  ~c(echo '{"transaction": "#{tx}"}' | http POST localhost:9656/transaction.submit) |>
  :os.cmd() |>
  Poison.decode!()

# create an in-flight transaction that uses tx's output as an input
in_flight_tx_bytes =
  Transaction.new([{child_tx_block_number, tx_index, 0}], [{alice.addr, eth, 7}]) |>
  DevCrypto.sign([bob.priv, <<>>]) |>
  Transaction.Signed.encode() |>
  Encoding.to_hex()

# get in-flight exit data for tx

%{"data" => get_in_flight_exit_response} =
  ~c(echo '{"txbytes": "#{in_flight_tx_bytes}"}' | http POST localhost:7434/in_flight_exit.get_data) |>
  :os.cmd() |>
  Poison.decode!()

# call root chain function that initiates in-flight exit
{:ok, txhash} =
  OMG.Eth.RootChain.in_flight_exit(
    get_in_flight_exit_response["in_flight_tx"] |> Encoding.from_hex(),
    get_in_flight_exit_response["input_txs"] |> Encoding.from_hex(),
    get_in_flight_exit_response["input_txs_inclusion_proofs"] |> Encoding.from_hex(),
    get_in_flight_exit_response["in_flight_tx_sigs"] |> Encoding.from_hex(),
    alice.addr
  )
{:ok, _} = Eth.WaitFor.eth_receipt(txhash)

# querying Ethereum for in-flight exits should return the initiated in-flight exit
{:ok, eth_height} = OMG.Eth.get_ethereum_height()
{:ok, [in_flight_exit]} = OMG.Eth.RootChain.get_in_flight_exit_starts(0, eth_height)
```
