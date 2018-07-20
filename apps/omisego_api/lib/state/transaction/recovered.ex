defmodule OmiseGO.API.State.Transaction.Recovered do
  @moduledoc """
  Representation of a Signed transaction, with addresses recovered from signatures (from Transaction.Signed)
  Intent is to allow concurent processing of signatures outside of serial processing in state.ex
  """

  alias OmiseGO.API.Crypto
  alias OmiseGO.API.State.Transaction

  @empty_signature <<0::size(520)>>
  @type signed_tx_hash_t() :: <<_::768>>

  defstruct [:signed_tx, :signed_tx_hash, spender1: nil, spender2: nil]

  @type t() :: %__MODULE__{
          signed_tx_hash: signed_tx_hash_t(),
          spender1: Crypto.address_t() | nil,
          spender2: Crypto.address_t() | nil,
          signed_tx: Transaction.Signed.t()
        }

  @spec recover_from(Transaction.Signed.t()) :: {:ok, t()} | any
  def recover_from(%Transaction.Signed{raw_tx: raw_tx, sig1: sig1, sig2: sig2} = signed_tx) do
    hash_no_spenders = Transaction.hash(raw_tx)

    with {:ok, spender1} <- get_spender(hash_no_spenders, sig1),
         {:ok, spender2} <- get_spender(hash_no_spenders, sig2),
         do:
           {:ok,
            %__MODULE__{
              signed_tx_hash: Transaction.Signed.signed_hash(signed_tx),
              spender1: spender1,
              spender2: spender2,
              signed_tx: signed_tx
            }}
  end

  defp get_spender(_hash_no_spenders, @empty_signature), do: {:ok, nil}
  defp get_spender(hash_no_spenders, sig), do: Crypto.recover_address(hash_no_spenders, sig)
end
