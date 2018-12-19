defmodule DemosTest do
  use ExUnitFixtures
  use ExUnit.Case, async: false
  use OMG.API.Fixtures
  use OMG.API.Integration.Fixtures
  use Plug.Test
  use Phoenix.ChannelTest

  alias OMG.API
  alias OMG.API.Utxo
  require Utxo
  alias OMG.Eth
  alias OMG.RPC.Client
  alias OMG.Watcher.Eventer.Event
  alias OMG.Watcher.Integration.TestHelper, as: IntegrationTest
  alias OMG.Watcher.Web.Channel
  alias OMG.Watcher.Web.Serializers.Response

  @moduletag :demos


  setup_all do
    {:ok, _} = Application.ensure_all_started(:briefly)
    :ok
  end

  def create_tmp_code_file(demo_file, module_name) do
    demo = File.read!(demo_file)  
    %{"code" => code} = Regex.named_captures(~r/```elixir(?<code>.*)```/is, demo)
    {:ok, path} = Briefly.create
    File.write!(path, """
      defmodule #{module_name} do
         defdelegate r(module), to: IEx.Helpers
         def run() do
            #{code}
         end
      end
      """)
    path
  end

  @tag fixtures: [:watcher_sandbox, :child_chain]
  test "demo_01", %{} do
    file = create_tmp_code_file("../../docs/demo_01.md", "Demo_01")
    IEx.Helpers.c(file)
    apply(String.to_atom("Elixir.Demo_01"), :run, [])
  end

  @tag fixtures: [:watcher_sandbox, :child_chain]
  test "demo_02", %{} do
    file = create_tmp_code_file("../../docs/demo_02.md", "Demo_02")
    IEx.Helpers.c(file)
    apply(String.to_atom("Elixir.Demo_02"), :run, [])
  end
end


