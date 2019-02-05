# Copyright 2018 OmiseGO Pte Ltd
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule OMG.Watcher.ExitProcessor.PersistenceTest do
  @moduledoc """
  Test focused on the persistence bits of `OMG.Watcher.ExitProcessor.Core`.

  The aim of this test is to ensure, that whatever state the processor ends up being in will be revived from the DB
  """

  use ExUnitFixtures
  use OMG.DB.Case, async: true

  alias OMG.API.DevCrypto
  alias OMG.API.State.Transaction
  alias OMG.API.Utxo
  alias OMG.Watcher.ExitProcessor.Core

  import OMG.API.TestHelper

  require Utxo

  @eth OMG.API.Crypto.zero_address()
  @not_eth <<1::size(160)>>
  @zero_address OMG.API.Crypto.zero_address()

  @early_blknum 1_000
  @late_blknum 10_000

  @utxo_pos1 Utxo.position(1, 0, 0)
  @utxo_pos2 Utxo.position(@late_blknum - 1_000, 0, 1)

  setup %{db_pid: db_pid} do
    :ok = OMG.DB.initiation_multiupdate(db_pid)
  end

  deffixture processor_empty() do
    {:ok, empty} = Core.init([], [], [])
    empty
  end

  @tag fixtures: [:processor_empty, :alice]
  test "persist started exits and loads persisted on init, not all exits active",
       %{processor_empty: processor, alice: alice, db_pid: db_pid} do
    # FIXME: dry against ExitProcessor.CoreTest? but I don't want to use fixtures here :(...
    exit_events = [
      %{amount: 10, currency: @eth, owner: alice.addr, utxo_pos: Utxo.Position.encode(@utxo_pos1), eth_height: 2},
      %{amount: 9, currency: @not_eth, owner: alice.addr, utxo_pos: Utxo.Position.encode(@utxo_pos2), eth_height: 4},
      %{amount: 9, currency: @not_eth, owner: alice.addr, utxo_pos: Utxo.Position.encode(@utxo_pos2), eth_height: 4}
    ]

    contract_statuses = [{alice.addr, @eth, 10}, {@zero_address, @eth, 10}, {alice.addr, @not_eth, 9}]

    processor =
      processor
      |> persist_new_exits(exit_events, contract_statuses, db_pid)

    assert processor == state_from(db_pid)
  end

  @tag fixtures: [:processor_empty, :alice]
  test "persist finalizations with various validities",
       %{processor_empty: processor, alice: alice, db_pid: db_pid} do
    # FIXME: dry against ExitProcessor.CoreTest? but I don't want to use fixtures here :(...
    exit_events = [
      %{amount: 10, currency: @eth, owner: alice.addr, utxo_pos: Utxo.Position.encode(@utxo_pos1), eth_height: 2},
      %{amount: 9, currency: @not_eth, owner: alice.addr, utxo_pos: Utxo.Position.encode(@utxo_pos2), eth_height: 4}
    ]

    contract_statuses = [{alice.addr, @eth, 10}, {@zero_address, @eth, 10}]

    processor =
      processor
      |> persist_new_exits(exit_events, contract_statuses, db_pid)
      |> persist_finalize_exits({[@utxo_pos1], [@utxo_pos2]}, db_pid)

    assert processor == state_from(db_pid)
  end

  @tag fixtures: [:processor_empty, :alice]
  test "persist challenges",
       %{processor_empty: processor, alice: alice, db_pid: db_pid} do
    # FIXME: dry against ExitProcessor.CoreTest? but I don't want to use fixtures here :(...
    exit_events = [
      %{amount: 10, currency: @eth, owner: alice.addr, utxo_pos: Utxo.Position.encode(@utxo_pos1), eth_height: 2},
      %{amount: 9, currency: @not_eth, owner: alice.addr, utxo_pos: Utxo.Position.encode(@utxo_pos2), eth_height: 4}
    ]

    contract_statuses = [{alice.addr, @eth, 10}, {@zero_address, @eth, 10}]

    processor =
      processor
      |> persist_new_exits(exit_events, contract_statuses, db_pid)
      |> persist_challenge_exits([@utxo_pos1], db_pid)

    assert processor == state_from(db_pid)
  end

  @tag fixtures: [:processor_empty, :alice, :carol]
  test "persist started ifes and loads persisted on init",
       %{processor_empty: processor, alice: alice, carol: carol, db_pid: db_pid} do
    # FIXME: dry against ExitProcessor.CoreTest? but I don't want to use fixtures here :(...
    txs = [
      Transaction.new([{1, 0, 0}, {1, 2, 1}], [{alice.addr, @eth, 1}]),
      Transaction.new([{2, 1, 0}, {2, 2, 1}], [{alice.addr, @eth, 1}, {carol.addr, @eth, 2}])
    ]

    processor =
      processor
      |> persist_new_ifes(txs, [[alice.priv], [alice.priv, carol.priv]], db_pid)

    assert processor == state_from(db_pid)
  end

  @tag fixtures: [:processor_empty, :alice, :carol]
  test "persist started ifes regardless of status",
       %{processor_empty: processor, alice: alice, carol: carol, db_pid: db_pid} do
    # FIXME: dry against ExitProcessor.CoreTest? but I don't want to use fixtures here :(...
    txs = [
      Transaction.new([{1, 0, 0}, {1, 2, 1}], [{alice.addr, @eth, 1}]),
      Transaction.new([{2, 1, 0}, {2, 2, 1}], [{alice.addr, @eth, 1}, {carol.addr, @eth, 2}])
    ]

    contract_statuses = [{1, <<1::192>>}, {0, <<0::192>>}]

    processor =
      processor
      |> persist_new_ifes(txs, [[alice.priv], [alice.priv, carol.priv]], contract_statuses, db_pid)

    assert processor == state_from(db_pid)
  end

  @tag fixtures: [:processor_empty, :alice]
  test "persist new piggybacks",
       %{processor_empty: processor, alice: alice, db_pid: db_pid} do
    # FIXME: dry against ExitProcessor.CoreTest? but I don't want to use fixtures here :(...
    tx = Transaction.new([{2, 1, 0}], [{alice.addr, @eth, 1}, {alice.addr, @eth, 2}])
    hash = Transaction.hash(tx)

    processor =
      processor
      |> persist_new_ifes([tx], [[alice.priv]], db_pid)
      |> persist_new_piggybacks([%{tx_hash: hash, output_index: 0}, %{tx_hash: hash, output_index: 4}], db_pid)
      |> persist_new_piggybacks([%{tx_hash: hash, output_index: 5}], db_pid)

    assert processor == state_from(db_pid)
  end

  # mimics `&OMG.Watcher.ExitProcessor.init/1`
  defp state_from(db_pid) do
    {:ok, db_exits} = OMG.DB.exit_infos(db_pid)
    {:ok, db_ifes} = OMG.DB.in_flight_exits_info(db_pid)
    {:ok, db_competitors} = OMG.DB.competitors_info(db_pid)

    {:ok, state} = Core.init(db_exits, db_ifes, db_competitors)
    state
  end

  defp persist_new_exits(processor, exit_events, contract_statuses, db_pid) do
    {processor, db_updates} = Core.new_exits(processor, exit_events, contract_statuses)
    assert :ok = OMG.DB.multi_update(db_updates, db_pid)
    processor
  end

  defp persist_finalize_exits(processor, validities, db_pid) do
    {processor, db_updates} = Core.finalize_exits(processor, validities)
    assert :ok = OMG.DB.multi_update(db_updates, db_pid)
    processor
  end

  defp persist_challenge_exits(processor, utxo_positions, db_pid) do
    {processor, db_updates} =
      Core.challenge_exits(processor, utxo_positions |> Enum.map(&%{utxo_pos: Utxo.Position.encode(&1)}))

    assert :ok = OMG.DB.multi_update(db_updates, db_pid)
    processor
  end

  defp persist_new_ifes(processor, txs, priv_keys, statuses \\ nil, db_pid) do
    # FIXME: dry against machinery in CorTest
    encoded_txs =
      txs
      |> Enum.map(&Transaction.encode/1)

    sigs =
      txs
      |> Enum.zip(priv_keys)
      |> Enum.map(fn {tx, keys} -> DevCrypto.sign(tx, keys) end)
      |> Enum.map(&Enum.join(&1.sigs))

    in_flight_exit_events =
      Enum.zip(encoded_txs, sigs)
      |> Enum.map(fn {txbytes, sigs} ->
        %{call_data: %{in_flight_tx: txbytes, in_flight_tx_sigs: sigs}, eth_height: 2}
      end)

    statuses = statuses || List.duplicate({1, <<1::192>>}, length(in_flight_exit_events))
    {processor, db_updates} = Core.new_in_flight_exits(processor, in_flight_exit_events, statuses)

    assert :ok = OMG.DB.multi_update(db_updates, db_pid)
    processor
  end

  defp persist_new_piggybacks(processor, piggybacks, db_pid) do
    {processor, db_updates} = Core.new_piggybacks(processor, piggybacks)

    assert :ok = OMG.DB.multi_update(db_updates, db_pid)
    processor
  end
end
