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

defmodule Msfailab.LLM.RegistryTest do
  use Msfailab.LLMCase, async: false

  alias Msfailab.LLM.Model
  alias Msfailab.LLM.Registry

  describe "init/1" do
    test "initializes with single provider returning models" do
      expect(ProviderMock, :configured?, fn -> true end)

      expect(ProviderMock, :list_models, fn ->
        {:ok,
         [
           %Model{name: "model-1", provider: :mock, context_window: 128_000},
           %Model{name: "model-2", provider: :mock, context_window: 200_000}
         ]}
      end)

      start_registry!()

      models = Registry.list_models()
      assert length(models) == 2
      assert Enum.any?(models, &(&1.name == "model-1"))
      assert Enum.any?(models, &(&1.name == "model-2"))
    end

    test "fails when no providers are configured" do
      expect(ProviderMock, :configured?, fn -> false end)

      Application.put_env(:msfailab, :llm_providers, [{ProviderMock, "test-model"}])

      assert {:error, _} =
               start_supervised(Registry)
    end

    test "fails when all providers fail to activate" do
      expect(ProviderMock, :configured?, fn -> true end)
      expect(ProviderMock, :list_models, fn -> {:error, :connection_failed} end)

      Application.put_env(:msfailab, :llm_providers, [{ProviderMock, "test-model"}])

      assert {:error, _} =
               start_supervised(Registry)
    end

    test "fails when no models are discovered" do
      expect(ProviderMock, :configured?, fn -> true end)
      expect(ProviderMock, :list_models, fn -> {:ok, []} end)

      Application.put_env(:msfailab, :llm_providers, [{ProviderMock, "test-model"}])

      assert {:error, _} =
               start_supervised(Registry)
    end

    test "uses provider default model when available" do
      expect(ProviderMock, :configured?, fn -> true end)

      expect(ProviderMock, :list_models, fn ->
        {:ok,
         [
           %Model{name: "other-model", provider: :mock, context_window: 128_000},
           %Model{name: "test-model", provider: :mock, context_window: 200_000}
         ]}
      end)

      start_registry!([{ProviderMock, "test-model"}])

      assert Registry.get_default_model() == "test-model"
    end

    test "uses first model after descending sort when MSFAILAB_DEFAULT_MODEL not set" do
      expect(ProviderMock, :configured?, fn -> true end)

      expect(ProviderMock, :list_models, fn ->
        {:ok,
         [
           %Model{name: "alpha-model", provider: :mock, context_window: 128_000},
           %Model{name: "zeta-model", provider: :mock, context_window: 200_000}
         ]}
      end)

      start_registry!([{ProviderMock, "nonexistent-default"}])

      # Default "*" matches all, sorted descending: zeta > alpha
      assert Registry.get_default_model() == "zeta-model"
    end
  end

  describe "list_models/0" do
    test "returns all cached models" do
      expect(ProviderMock, :configured?, fn -> true end)

      expect(ProviderMock, :list_models, fn ->
        {:ok,
         [
           %Model{name: "model-a", provider: :mock, context_window: 100_000},
           %Model{name: "model-b", provider: :mock, context_window: 200_000}
         ]}
      end)

      start_registry!()

      models = Registry.list_models()
      assert length(models) == 2
    end
  end

  describe "get_model/1" do
    test "returns model when found" do
      expect(ProviderMock, :configured?, fn -> true end)

      expect(ProviderMock, :list_models, fn ->
        {:ok, [%Model{name: "my-model", provider: :mock, context_window: 128_000}]}
      end)

      start_registry!()

      assert {:ok, %Model{name: "my-model"}} = Registry.get_model("my-model")
    end

    test "returns error when model not found" do
      expect(ProviderMock, :configured?, fn -> true end)

      expect(ProviderMock, :list_models, fn ->
        {:ok, [%Model{name: "existing-model", provider: :mock, context_window: 128_000}]}
      end)

      start_registry!()

      assert {:error, :not_found} = Registry.get_model("nonexistent")
    end
  end

  describe "get_default_model/0" do
    test "returns the default model name" do
      expect(ProviderMock, :configured?, fn -> true end)

      expect(ProviderMock, :list_models, fn ->
        {:ok, [%Model{name: "default-model", provider: :mock, context_window: 128_000}]}
      end)

      start_registry!([{ProviderMock, "default-model"}])

      assert Registry.get_default_model() == "default-model"
    end
  end

  describe "MSFAILAB_DEFAULT_MODEL environment variable" do
    test "overrides provider default when set and valid" do
      System.put_env("MSFAILAB_DEFAULT_MODEL", "env-model")

      expect(ProviderMock, :configured?, fn -> true end)

      expect(ProviderMock, :list_models, fn ->
        {:ok,
         [
           %Model{name: "provider-default", provider: :mock, context_window: 128_000},
           %Model{name: "env-model", provider: :mock, context_window: 200_000}
         ]}
      end)

      start_registry!([{ProviderMock, "provider-default"}])

      assert Registry.get_default_model() == "env-model"

      System.delete_env("MSFAILAB_DEFAULT_MODEL")
    end

    test "fails when MSFAILAB_DEFAULT_MODEL doesn't match any discovered model" do
      System.put_env("MSFAILAB_DEFAULT_MODEL", "nonexistent-model")

      expect(ProviderMock, :configured?, fn -> true end)

      expect(ProviderMock, :list_models, fn ->
        {:ok, [%Model{name: "actual-model", provider: :mock, context_window: 128_000}]}
      end)

      Application.put_env(:msfailab, :llm_providers, [{ProviderMock, "actual-model"}])

      assert {:error, _} = start_supervised(Registry)

      System.delete_env("MSFAILAB_DEFAULT_MODEL")
    end
  end

  describe "multiple providers" do
    test "merges models from multiple providers" do
      # Create a second mock for the second provider
      Mox.defmock(SecondProviderMock, for: Msfailab.LLM.Provider)

      expect(ProviderMock, :configured?, fn -> true end)

      expect(ProviderMock, :list_models, fn ->
        {:ok, [%Model{name: "provider1-model", provider: :mock1, context_window: 128_000}]}
      end)

      expect(SecondProviderMock, :configured?, fn -> true end)

      expect(SecondProviderMock, :list_models, fn ->
        {:ok, [%Model{name: "provider2-model", provider: :mock2, context_window: 200_000}]}
      end)

      start_registry!([
        {ProviderMock, "provider1-model"},
        {SecondProviderMock, "provider2-model"}
      ])

      models = Registry.list_models()
      assert length(models) == 2
      assert Enum.any?(models, &(&1.name == "provider1-model"))
      assert Enum.any?(models, &(&1.name == "provider2-model"))
    end

    test "uses first model after descending sort across all providers" do
      Mox.defmock(ThirdProviderMock, for: Msfailab.LLM.Provider)

      expect(ProviderMock, :configured?, fn -> true end)

      expect(ProviderMock, :list_models, fn ->
        {:ok, [%Model{name: "alpha-model", provider: :mock1, context_window: 128_000}]}
      end)

      expect(ThirdProviderMock, :configured?, fn -> true end)

      expect(ThirdProviderMock, :list_models, fn ->
        {:ok, [%Model{name: "zeta-model", provider: :mock2, context_window: 200_000}]}
      end)

      start_registry!([
        {ProviderMock, "alpha-model"},
        {ThirdProviderMock, "zeta-model"}
      ])

      # Default "*" matches all, sorted descending: zeta > alpha
      assert Registry.get_default_model() == "zeta-model"
    end

    test "continues when one provider fails" do
      Mox.defmock(FourthProviderMock, for: Msfailab.LLM.Provider)

      expect(ProviderMock, :configured?, fn -> true end)
      expect(ProviderMock, :list_models, fn -> {:error, :connection_refused} end)

      expect(FourthProviderMock, :configured?, fn -> true end)

      expect(FourthProviderMock, :list_models, fn ->
        {:ok, [%Model{name: "working-model", provider: :mock, context_window: 128_000}]}
      end)

      start_registry!([
        {ProviderMock, "failed-provider-default"},
        {FourthProviderMock, "working-model"}
      ])

      models = Registry.list_models()
      assert length(models) == 1
      assert hd(models).name == "working-model"
    end
  end
end
