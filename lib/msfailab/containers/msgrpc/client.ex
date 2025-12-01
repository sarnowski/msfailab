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
# Reason: Behaviour module - only defines callbacks, no executable code
defmodule Msfailab.Containers.Msgrpc.Client do
  @moduledoc """
  Behaviour defining the contract for MSGRPC client operations.

  This abstraction enables testing console management logic without
  actual Metasploit containers by using Mox to create mock implementations.

  ## Protocol

  MSGRPC uses MessagePack encoding over HTTP POST to /api/.
  All requests (except auth.login) require an authentication token.

  Requests are MessagePack-encoded arrays: `["method.name", arg1, arg2, ...]`
  Responses are MessagePack-encoded maps with result data.

  ## Usage

      client = Application.get_env(:msfailab, :msgrpc_client)
      {:ok, token} = client.login(endpoint, "password")
      {:ok, console} = client.console_create(endpoint, token)
      {:ok, _} = client.console_write(endpoint, token, console["id"], "help\\n")
      {:ok, result} = client.console_read(endpoint, token, console["id"])
  """

  @typedoc "MSGRPC endpoint (host and port)"
  @type endpoint :: %{host: String.t(), port: pos_integer()}

  @typedoc "MSGRPC authentication token"
  @type token :: String.t()

  @typedoc "MSGRPC console ID"
  @type console_id :: String.t()

  @doc """
  Authenticates with the MSGRPC server and returns a session token.

  The token is required for all subsequent API calls.

  ## Parameters

  - `endpoint` - The MSGRPC endpoint (host and port)
  - `password` - The RPC password
  - `username` - Optional username (defaults to "msf")
  """
  @callback login(endpoint(), String.t(), String.t()) :: {:ok, token()} | {:error, term()}

  @doc """
  Creates a new console session.

  Returns console info including the console ID needed for read/write operations.
  """
  @callback console_create(endpoint(), token()) :: {:ok, map()} | {:error, term()}

  @doc """
  Destroys a console session.
  """
  @callback console_destroy(endpoint(), token(), console_id()) :: :ok | {:error, term()}

  @doc """
  Writes data to a console.

  The data should include a trailing newline to execute commands.
  Returns the number of bytes written.
  """
  @callback console_write(endpoint(), token(), console_id(), String.t()) ::
              {:ok, non_neg_integer()} | {:error, term()}

  @doc """
  Reads available output from a console.

  Returns a map with:
  - `data`: Output text since last read (may be empty)
  - `busy`: Whether the console is executing a command
  - `prompt`: Current prompt string (when not busy)
  """
  @callback console_read(endpoint(), token(), console_id()) :: {:ok, map()} | {:error, term()}

  @doc """
  Calls a generic MSGRPC method with the given token and arguments.

  Returns the response map on success or an error tuple on failure.
  """
  @callback call(endpoint(), token(), String.t(), list()) :: {:ok, map()} | {:error, term()}
end

# coveralls-ignore-stop
