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

# coveralls-ignore-start
# Reason: Test support module - not production code
defmodule Msfailab.Containers.Msgrpc.ClientStub do
  @moduledoc """
  Test stub for the MSGRPC client.

  Returns successful responses for all operations. Use this as a default stub
  in tests, then override specific methods with Mox expectations when needed.
  """

  @behaviour Msfailab.Containers.Msgrpc.Client

  @impl true
  def login(_endpoint, _password, _username \\ "msf") do
    {:ok, "test_token_#{:rand.uniform(100_000)}"}
  end

  @impl true
  def call(_endpoint, _token, _method, _args) do
    {:ok, %{}}
  end

  @impl true
  def console_create(_endpoint, _token) do
    {:ok, %{"id" => "console_#{:rand.uniform(100_000)}"}}
  end

  @impl true
  def console_destroy(_endpoint, _token, _console_id) do
    :ok
  end

  @impl true
  def console_write(_endpoint, _token, _console_id, data) do
    {:ok, byte_size(data)}
  end

  @impl true
  def console_read(_endpoint, _token, _console_id) do
    {:ok, %{"data" => "", "busy" => false, "prompt" => "msf6 > "}}
  end
end

# coveralls-ignore-stop
