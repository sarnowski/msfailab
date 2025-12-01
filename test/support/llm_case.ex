# Metasploit Framework AI Lab - Collaborative security research with AI agents
# Copyright (C) 2025 Tobias Sarnowski
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.

defmodule Msfailab.LLMCase do
  @moduledoc """
  Test case for LLM-related tests.

  Sets up Mox mocks for LLM providers and manages the LLM Registry lifecycle
  for integration testing.

  ## Example

      defmodule Msfailab.LLM.RegistryTest do
        use Msfailab.LLMCase, async: false

        test "initializes with configured providers" do
          expect(ProviderMock, :configured?, fn -> true end)
          expect(ProviderMock, :list_models, fn ->
            {:ok, [%Model{name: "test-model", provider: :mock, context_window: 128_000}]}
          end)

          start_registry!()

          assert [%Model{name: "test-model"}] = Msfailab.LLM.list_models()
        end
      end
  """

  use ExUnit.CaseTemplate

  alias Msfailab.LLM.ProviderMock

  using do
    quote do
      import Mox

      alias Msfailab.LLM.Model
      alias Msfailab.LLM.ProviderMock

      # Verify Mox expectations after each test
      setup :verify_on_exit!

      @doc """
      Starts the LLM Registry with the test provider configuration.
      Call this after setting up Mox expectations.
      """
      def start_registry!(providers \\ [{ProviderMock, "test-model"}]) do
        Application.put_env(:msfailab, :llm_providers, providers)
        start_supervised!(Msfailab.LLM.Registry)
      end
    end
  end

  setup _tags do
    # Set Mox to global mode so spawned GenServer processes can access expectations.
    # This requires tests to run with async: false.
    Mox.set_mox_global(self())

    on_exit(fn ->
      # Clean up provider config after each test
      Application.delete_env(:msfailab, :llm_providers)
    end)

    :ok
  end
end
