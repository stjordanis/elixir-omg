# Watching a valid and invalid child chain

The following demo is a mix of commands executed in IEx and some Unix shell.

Run a developer's Child chain server, Watcher and start IEx REPL with code and config loaded, as described in README.md instructions.

**NOTE** you'll find it useful to run the child chain server with a IEx to recompile:
        iex -S mix run --config ...


```elixir

### PREPARATIONS

# we're going to be using the exthereum's client to geth's JSON RPC
{:ok, _} = Application.ensure_all_started(:ethereumex)

alias OMG.{API, Eth}
alias OMG.API.Crypto
alias OMG.API.DevCrypto
alias OMG.API.State.Transaction
alias OMG.API.TestHelper
alias OMG.API.Integration.DepositHelper

alice = TestHelper.generate_entity()
bob = TestHelper.generate_entity()
eth = Crypto.zero_address()

alice_enc = Crypto.encode_address!(alice.addr)
bob_enc = Crypto.encode_address!(bob.addr)

{:ok, _} = Eth.DevHelpers.import_unlock_fund(alice)
{:ok, _} = Eth.DevHelpers.import_unlock_fund(bob)

# sends deposit transactions _to Ethereum_
# we need to uncover the height at which the deposit went through on the root chain
bob_deposit_blknum = DepositHelper.deposit_to_child_chain(bob.addr, 10)
alice_deposit_blknum = DepositHelper.deposit_to_child_chain(alice.addr, 10)

### START DEMO HERE

# we've got alice, bob prepared, also an honest child chain is running with a watcher connected
# NOTE: if you stopped and started geth after setting up alice and bob you need to unlock their accounts
#       (see [this section in the README](../README.md#prepare-and-configure-the-root-chain-contract))

# 1/ Demonstrate Watcher consuming honest transactions

# create and prepare transaction for signing
tx =
  Transaction.new([{alice_deposit_blknum, 0, 0}], [{bob.addr, eth, 7}, {alice.addr, eth, 3}]) |>
  DevCrypto.sign([alice.priv, <<>>]) |>
  Transaction.Signed.encode() |>
  OMG.RPC.Web.Encoding.to_hex()

# submits a transaction to the child chain
# this only will work after the deposit has been "consumed" by the child chain, be patient (~15sec)
# use the hex-encoded tx bytes and `transaction.submit` Http-RPC method described in README.md for child chain server
%{"data" => %{"tx_hash" => tx1_hash}} =
  ~c(echo '{"transaction": "#{tx}"}' | http POST localhost:9656/transaction.submit) |>
  :os.cmd() |>
  Poison.decode!()

# see the Watcher getting a 1-txs block

# 2/ Using the Watcher

# we grabbed the first transaction hash as returned by the Child chain server's API (response to `http`'s request)

~c(echo '{"id": "#{tx1_hash}"}' | http POST localhost:7434/transaction.get) |>
to_charlist() |>
:os.cmd() |>
Poison.decode!()

%{"data" => [_bobs_deposit, %{"blknum" => exiting_utxo_blknum, "txindex" => 0, "oindex" => 0}]} =
  ~c(echo '{"address": "#{bob_enc}"}' | http POST localhost:7434/account.get_utxos) |>
  to_charlist() |>
  :os.cmd() |>
  Poison.decode!()

# 3/ Exiting, challenging invalid exits

exiting_utxopos = OMG.API.Utxo.Position.encode({:utxo_position, exiting_utxo_blknum, 0, 0})

%{"data" => composed_exit} =
  ~c(echo '{"utxo_pos": #{exiting_utxopos}}' | http POST localhost:7434/utxo.get_exit_data) |>
  to_charlist() |>
  :os.cmd() |>
  Poison.decode!()

tx2 =
  Transaction.new([{exiting_utxo_blknum, 0, 0}], [{bob.addr, eth, 7}]) |>
  DevCrypto.sign([bob.priv, <<>>]) |>
  Transaction.Signed.encode() |>
  OMG.RPC.Web.Encoding.to_hex()

# FIRST you need to spend in transaction as above, so that the exit then is in fact invalid and challengeable
~c(echo '{"transaction": "#{tx2}"}' | http POST localhost:9656/transaction.submit) |>
:os.cmd() |>
Poison.decode!()

{:ok, txbytes} = OMG.RPC.Web.Encoding.from_hex(composed_exit["txbytes"])
{:ok, proof} = OMG.RPC.Web.Encoding.from_hex(composed_exit["proof"])
{:ok, txhash} =
  Eth.RootChain.start_exit(
    composed_exit["utxo_pos"],
    txbytes,
    proof,
    bob.addr
  )
Eth.WaitFor.eth_receipt(txhash)

%{"data" => challenge} =
  ~c(echo '{"utxo_pos": #{exiting_utxopos}}' | http POST localhost:7434/utxo.get_challenge_data) |>
  to_charlist() |>
  :os.cmd() |>
  Poison.decode!()

{:ok, txbytes} = OMG.RPC.Web.Encoding.from_hex(challenge["txbytes"])
{:ok, sig} = OMG.RPC.Web.Encoding.from_hex(challenge["sig"])
{:ok, txhash} =
  OMG.Eth.RootChain.challenge_exit(
    challenge["utxo_pos"],
    txbytes,
    challenge["input_index"],
    sig,
    alice.addr
  )
{:ok, _} = Eth.WaitFor.eth_receipt(txhash)

# 4/ let's introduce a delay into the process of getting child block contents from the child chain server

# If we introduce a 5 second sleep, the Watcher will have a hard time getting a block (requests time out in 5 seconds).
# Some attempts will pass, some will fail and with the withholding threshold set to 10 seconds, we'll have block withholding stop the Watcher and print out an error (and fire events for machines)

# put `Process.sleep 5_000` in API module, around line 48

# now, with the code "broken" go to the `iex` REPL of the child chain and recompile the module

r(OMG.API)

# submit a transaction that will get mined in a new block
tx3 =
  Transaction.new([{bob_deposit_blknum, 0, 0}], [{bob.addr, eth, 7}, {alice.addr, eth, 3}]) |>
  DevCrypto.sign([bob.priv, <<>>]) |>
  Transaction.Signed.encode() |>
  OMG.RPC.Web.Encoding.to_hex()

%{"success" => true} =
  ~c(echo '{"transaction": "#{tx3}"}' | http POST localhost:9656/transaction.submit) |>
  :os.cmd() |>
  Poison.decode!()

# see Watcher's console logs to see the struggle and final give-in. You can restart the Watcher many times

# when you're done, undo the breakage and recompile again. Running the Watcher should allow it to sync

# 5/ invalid block submitted

# let's break the Child chain now and say that duplicates every transaction submitted!

# in order to do that, you need to duplicate the `|> add_pending_tx(recovered_tx)` in API.State.Core module,
# around line 160

# now, with the code "broken" go to the `iex` REPL of the child chain and recompile the module

r(OMG.API.State.Core)

# let's do a broken spend:

# grab an utxo that bob can spend
%{"data" => [_bobs_deposit, %{"blknum" => spend_blknum, "txindex" => 0, "oindex" => 0}]} =
  ~c(echo '{"address": "#{bob_enc}"}' | http POST localhost:7434/utxo.get) |>
  to_charlist() |>
  :os.cmd() |>
  Poison.decode!()

tx4 =
  Transaction.new([{spend_blknum, 0, 0}], [{bob.addr, eth, 7}]) |>
  DevCrypto.sign([bob.priv, <<>>]) |>
  Transaction.Signed.encode() |>
  OMG.RPC.Web.Encoding.to_hex()

# and send using httpie
~c(echo '{"transaction": "#{tx4}"}' | http POST localhost:9656/transaction.submit) |>
:os.cmd() |>
Poison.decode!()

# See the Watcher stop on an error
```
