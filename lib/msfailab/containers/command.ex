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

defmodule Msfailab.Containers.Command do
  @moduledoc """
  Represents a command execution with its lifecycle and accumulated output.

  Commands are tracked by the Container GenServer from submission through
  completion. Each command has a unique ID for correlation with events.

  ## Command Types

  - `:metasploit` - Command sent to the Metasploit console via MSGRPC
  - `:bash` - Shell command executed in the container via Docker exec

  ## Lifecycle

  1. Created with `new/2` when command is submitted
  2. Output accumulated via `append_output/2` as it becomes available
  3. Marked finished via `finish/2` or `finish/3` when execution completes
  """

  @type command_type :: :metasploit | :bash
  @type status :: :running | :finished | :error

  @type t :: %__MODULE__{
          id: String.t(),
          type: command_type(),
          command: String.t(),
          status: status(),
          output: String.t(),
          prompt: String.t(),
          exit_code: integer() | nil,
          error: term() | nil,
          started_at: DateTime.t()
        }

  @enforce_keys [:id, :type, :command, :status, :output, :prompt, :started_at]
  defstruct [:id, :type, :command, :status, :output, :prompt, :exit_code, :error, :started_at]

  @doc """
  Creates a new command in running state.

  ## Examples

      iex> cmd = Command.new(:metasploit, "db_status")
      iex> cmd.type
      :metasploit
      iex> cmd.status
      :running
      iex> cmd.output
      ""
      iex> cmd.prompt
      ""
  """
  @spec new(command_type(), String.t()) :: t()
  def new(type, command) when type in [:metasploit, :bash] do
    %__MODULE__{
      id: generate_id(),
      type: type,
      command: command,
      status: :running,
      output: "",
      prompt: "",
      exit_code: nil,
      started_at: DateTime.utc_now()
    }
  end

  @doc """
  Appends output to the command's accumulated output buffer.

  ## Examples

      iex> cmd = Command.new(:bash, "ls") |> Command.append_output("file1.txt\n")
      iex> cmd.output
      "file1.txt\n"
  """
  @spec append_output(t(), String.t()) :: t()
  def append_output(%__MODULE__{} = cmd, output) when is_binary(output) do
    %{cmd | output: cmd.output <> output}
  end

  @doc """
  Sets the current console prompt.

  The prompt is replaced (not accumulated) since it represents
  the current console state.

  ## Examples

      iex> cmd = Command.new(:metasploit, "use exploit/multi/handler")
      iex> cmd = Command.set_prompt(cmd, "msf6 exploit(multi/handler) > ")
      iex> cmd.prompt
      "msf6 exploit(multi/handler) > "
  """
  @spec set_prompt(t(), String.t()) :: t()
  def set_prompt(%__MODULE__{} = cmd, prompt) when is_binary(prompt) do
    %{cmd | prompt: prompt}
  end

  @doc """
  Marks the command as finished.

  For bash commands, an exit code should be provided.
  For metasploit commands, exit code is not applicable.

  ## Examples

      iex> cmd = Command.new(:bash, "ls") |> Command.finish(exit_code: 0)
      iex> cmd.status
      :finished
      iex> cmd.exit_code
      0
  """
  @spec finish(t(), keyword()) :: t()
  def finish(%__MODULE__{} = cmd, opts \\ []) do
    %{cmd | status: :finished, exit_code: Keyword.get(opts, :exit_code)}
  end

  @doc """
  Marks the command as errored.

  Used when a command cannot complete due to external failure
  (e.g., container stopped, console died).

  ## Examples

      iex> cmd = Command.new(:bash, "ls") |> Command.error(:container_stopped)
      iex> cmd.status
      :error
      iex> cmd.error
      :container_stopped
  """
  @spec error(t(), term()) :: t()
  def error(%__MODULE__{} = cmd, error_reason) do
    %{cmd | status: :error, error: error_reason}
  end

  @doc """
  Returns whether the command is still running.
  """
  @spec running?(t()) :: boolean()
  def running?(%__MODULE__{status: :running}), do: true
  def running?(%__MODULE__{}), do: false

  # Private functions

  defp generate_id do
    :crypto.strong_rand_bytes(8)
    |> Base.encode16(case: :lower)
  end
end
