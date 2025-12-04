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

defmodule Msfailab.Tracks.TrackServer.TurnTest do
  use Msfailab.DataCase, async: true

  alias Msfailab.LLM.Events, as: LLMEvents
  alias Msfailab.Tracks.ChatEntry
  alias Msfailab.Tracks.TrackServer.State.Console, as: ConsoleState
  alias Msfailab.Tracks.TrackServer.State.Stream, as: StreamState
  alias Msfailab.Tracks.TrackServer.State.Turn, as: TurnState
  alias Msfailab.Tracks.TrackServer.Turn

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  defp make_turn(attrs) do
    %TurnState{
      status: Keyword.get(attrs, :status, :idle),
      turn_id: Keyword.get(attrs, :turn_id),
      model: Keyword.get(attrs, :model),
      llm_ref: Keyword.get(attrs, :llm_ref),
      tool_invocations: Keyword.get(attrs, :tool_invocations, %{}),
      command_to_tool: Keyword.get(attrs, :command_to_tool, %{}),
      last_cache_context: Keyword.get(attrs, :last_cache_context)
    }
  end

  defp make_console(attrs \\ []) do
    %ConsoleState{
      status: Keyword.get(attrs, :status, :ready),
      current_prompt: Keyword.get(attrs, :current_prompt, "msf6 >"),
      history: Keyword.get(attrs, :history, []),
      command_id: Keyword.get(attrs, :command_id)
    }
  end

  defp make_tool_invocation(tool_call_id, tool_name, status, opts \\ []) do
    %{
      tool_call_id: tool_call_id,
      tool_name: tool_name,
      arguments: Keyword.get(opts, :arguments, %{}),
      status: status,
      command_id: Keyword.get(opts, :command_id),
      started_at: Keyword.get(opts, :started_at)
    }
  end

  defp make_tool_entry(id, position, tool_name, status, opts \\ []) do
    ChatEntry.tool_invocation(
      id,
      position,
      Keyword.get(opts, :tool_call_id, "call_#{id}"),
      tool_name,
      Keyword.get(opts, :arguments, %{}),
      status,
      console_prompt: Keyword.get(opts, :console_prompt, "msf6 >")
    )
  end

  # ===========================================================================
  # Reconciliation Engine Tests
  # ===========================================================================

  describe "reconcile/4 - idle turn" do
    test "returns no_action when status is idle" do
      turn = make_turn(status: :idle)
      console = make_console()
      context = %{track_id: 1, model: "test", autonomous: false}

      assert :no_action = Turn.reconcile(turn, console, [], context)
    end

    test "returns no_action when status is finished" do
      turn = make_turn(status: :finished)
      console = make_console()
      context = %{track_id: 1, model: "test", autonomous: false}

      assert :no_action = Turn.reconcile(turn, console, [], context)
    end

    test "returns no_action when status is error" do
      turn = make_turn(status: :error)
      console = make_console()
      context = %{track_id: 1, model: "test", autonomous: false}

      assert :no_action = Turn.reconcile(turn, console, [], context)
    end
  end

  describe "reconcile/4 - pending approvals" do
    test "transitions to pending_approval when pending tools exist" do
      tool_inv = make_tool_invocation("call_1", "msf_command", :pending)

      turn = make_turn(status: :streaming, tool_invocations: %{1 => tool_inv})
      console = make_console()
      context = %{track_id: 1, model: "test", autonomous: false}

      {new_turn, _entries, actions} = Turn.reconcile(turn, console, [], context)

      assert new_turn.status == :pending_approval
      assert :broadcast_chat_state in actions
    end

    test "returns no_action when already in pending_approval" do
      tool_inv = make_tool_invocation("call_1", "msf_command", :pending)

      turn = make_turn(status: :pending_approval, tool_invocations: %{1 => tool_inv})
      console = make_console()
      context = %{track_id: 1, model: "test", autonomous: false}

      assert :no_action = Turn.reconcile(turn, console, [], context)
    end
  end

  describe "reconcile/4 - tool execution" do
    test "executes next sequential tool when console ready" do
      tool_inv =
        make_tool_invocation("call_1", "msf_command", :approved,
          arguments: %{"command" => "help"}
        )

      entry = make_tool_entry(1, 1, "msf_command", :approved, arguments: %{"command" => "help"})

      turn = make_turn(status: :executing_tools, tool_invocations: %{1 => tool_inv})
      console = make_console(status: :ready)
      context = %{track_id: 1, model: "test", autonomous: false}

      {new_turn, new_entries, actions} = Turn.reconcile(turn, console, [entry], context)

      assert new_turn.status == :executing_tools
      assert new_turn.tool_invocations[1].status == :executing
      assert Enum.at(new_entries, 0).tool_status == :executing
      assert {:send_msf_command, "help"} in actions
    end

    test "executes all parallel tools (bash_command) at once" do
      tool_inv1 =
        make_tool_invocation("call_1", "bash_command", :approved,
          arguments: %{"command" => "ls -la"}
        )

      tool_inv2 =
        make_tool_invocation("call_2", "bash_command", :approved,
          arguments: %{"command" => "pwd"}
        )

      entry1 =
        make_tool_entry(1, 1, "bash_command", :approved, arguments: %{"command" => "ls -la"})

      entry2 = make_tool_entry(2, 2, "bash_command", :approved, arguments: %{"command" => "pwd"})

      turn =
        make_turn(
          status: :executing_tools,
          tool_invocations: %{1 => tool_inv1, 2 => tool_inv2}
        )

      console = make_console(status: :ready)
      context = %{track_id: 1, model: "test", autonomous: false}

      {new_turn, new_entries, actions} = Turn.reconcile(turn, console, [entry1, entry2], context)

      # Both tools should be marked as executing
      assert new_turn.tool_invocations[1].status == :executing
      assert new_turn.tool_invocations[2].status == :executing
      assert Enum.at(new_entries, 0).tool_status == :executing
      assert Enum.at(new_entries, 1).tool_status == :executing

      # Both bash commands should be sent
      assert {:send_bash_command, 1, "ls -la"} in actions
      assert {:send_bash_command, 2, "pwd"} in actions
    end

    test "executes parallel tools even when sequential tools exist" do
      # When we have a mix of parallel and sequential tools,
      # parallel tools can run while console is busy with sequential
      sequential = make_tool_invocation("call_1", "msf_command", :executing)

      parallel =
        make_tool_invocation("call_2", "bash_command", :approved,
          arguments: %{"command" => "echo hi"}
        )

      entry1 = make_tool_entry(1, 1, "msf_command", :executing)

      entry2 =
        make_tool_entry(2, 2, "bash_command", :approved, arguments: %{"command" => "echo hi"})

      turn =
        make_turn(status: :executing_tools, tool_invocations: %{1 => sequential, 2 => parallel})

      console = make_console(status: :ready)
      context = %{track_id: 1, model: "test", autonomous: false}

      {new_turn, new_entries, actions} = Turn.reconcile(turn, console, [entry1, entry2], context)

      # The parallel tool should be executed
      assert new_turn.tool_invocations[2].status == :executing
      assert Enum.at(new_entries, 1).tool_status == :executing
      assert {:send_bash_command, 2, "echo hi"} in actions
    end

    # Note: Turn no longer blocks execution based on console status or other
    # executing tools. ContainerExecutor handles console readiness via retries,
    # and ExecutionManager handles sequential ordering via mutex groups.
    # Tests for these behaviors belong in container_executor_test.exs and
    # execution_manager_test.exs respectively.
  end

  describe "reconcile/4 - turn completion" do
    test "completes turn when streaming with no tools" do
      turn = make_turn(status: :streaming, turn_id: "turn-123", tool_invocations: %{})
      console = make_console()
      context = %{track_id: 1, model: "test", autonomous: false}

      {new_turn, _entries, actions} = Turn.reconcile(turn, console, [], context)

      assert new_turn.status == :finished
      assert {:update_turn_status, "turn-123", "finished"} in actions
    end
  end

  # ===========================================================================
  # Stream Complete/Error Tests
  # ===========================================================================

  describe "handle_stream_complete/2" do
    test "handles tool_use stop reason" do
      complete = %LLMEvents.StreamComplete{stop_reason: :tool_use, cache_context: %{key: "value"}}
      turn = make_turn(status: :streaming, llm_ref: make_ref())

      {new_turn, actions} = Turn.handle_stream_complete(turn, complete)

      assert new_turn.llm_ref == nil
      assert new_turn.last_cache_context == %{key: "value"}
      assert :reconcile in actions
      assert :broadcast_chat_state in actions
    end

    test "handles normal completion with turn_id" do
      complete = %LLMEvents.StreamComplete{stop_reason: :end_turn, cache_context: nil}
      turn = make_turn(status: :streaming, turn_id: "turn-123", llm_ref: make_ref())

      {new_turn, actions} = Turn.handle_stream_complete(turn, complete)

      assert new_turn.status == :finished
      assert new_turn.turn_id == nil
      assert new_turn.llm_ref == nil
      assert new_turn.tool_invocations == %{}
      assert {:update_turn_status, "turn-123", "finished"} in actions
    end

    test "handles normal completion without turn_id" do
      complete = %LLMEvents.StreamComplete{stop_reason: :end_turn, cache_context: nil}
      turn = make_turn(status: :streaming, turn_id: nil)

      {new_turn, actions} = Turn.handle_stream_complete(turn, complete)

      assert new_turn.status == :finished
      assert actions == [:broadcast_chat_state]
    end
  end

  describe "handle_stream_error/1" do
    test "marks turn as error with turn_id" do
      turn = make_turn(status: :streaming, turn_id: "turn-123", llm_ref: make_ref())

      {new_turn, actions} = Turn.handle_stream_error(turn)

      assert new_turn.status == :error
      assert new_turn.llm_ref == nil
      assert new_turn.tool_invocations == %{}
      assert {:update_turn_status, "turn-123", "error"} in actions
    end

    test "marks turn as error without turn_id" do
      turn = make_turn(status: :streaming, turn_id: nil)

      {new_turn, actions} = Turn.handle_stream_error(turn)

      assert new_turn.status == :error
      assert actions == [:broadcast_chat_state]
    end
  end

  # ===========================================================================
  # Tool Approval Tests
  # ===========================================================================

  describe "approve_tool/3" do
    test "approves pending tool" do
      tool_inv = make_tool_invocation("call_1", "msf_command", :pending)
      entry = make_tool_entry(1, 1, "msf_command", :pending)

      turn = make_turn(status: :pending_approval, tool_invocations: %{1 => tool_inv})

      {:ok, new_turn, new_entries, actions} = Turn.approve_tool(turn, [entry], 1)

      assert new_turn.tool_invocations[1].status == :approved
      assert Enum.at(new_entries, 0).tool_status == :approved
      assert {:update_tool_status, 1, "approved", []} in actions
      assert :reconcile in actions
    end

    test "returns error for unknown entry_id" do
      turn = make_turn(tool_invocations: %{})

      assert {:error, :not_found} = Turn.approve_tool(turn, [], 999)
    end

    test "returns error for non-pending tool" do
      tool_inv = make_tool_invocation("call_1", "msf_command", :approved)

      turn = make_turn(tool_invocations: %{1 => tool_inv})

      assert {:error, :invalid_status} = Turn.approve_tool(turn, [], 1)
    end
  end

  describe "deny_tool/4" do
    test "denies pending tool" do
      tool_inv = make_tool_invocation("call_1", "msf_command", :pending)
      entry = make_tool_entry(1, 1, "msf_command", :pending)

      turn = make_turn(status: :pending_approval, tool_invocations: %{1 => tool_inv})

      {:ok, new_turn, new_entries, actions} = Turn.deny_tool(turn, [entry], 1, "not safe")

      assert new_turn.tool_invocations[1].status == :denied
      assert Enum.at(new_entries, 0).tool_status == :denied
      assert {:update_tool_status, 1, "denied", [denied_reason: "not safe"]} in actions
      assert :reconcile in actions
    end

    test "returns error for unknown entry_id" do
      turn = make_turn(tool_invocations: %{})

      assert {:error, :not_found} = Turn.deny_tool(turn, [], 999, "reason")
    end

    test "returns error for non-pending tool" do
      tool_inv = make_tool_invocation("call_1", "msf_command", :executing)

      turn = make_turn(tool_invocations: %{1 => tool_inv})

      assert {:error, :invalid_status} = Turn.deny_tool(turn, [], 1, "reason")
    end
  end

  # ===========================================================================
  # Tool Execution Tests
  # ===========================================================================

  describe "start_tool_execution/4" do
    @context %{workspace_slug: "test-workspace"}

    test "starts execution for msf_command tool" do
      tool_inv =
        make_tool_invocation("call_1", "msf_command", :approved,
          arguments: %{"command" => "help"}
        )

      entry = make_tool_entry(1, 1, "msf_command", :approved, arguments: %{"command" => "help"})

      turn = make_turn(status: :executing_tools, tool_invocations: %{1 => tool_inv})

      {new_turn, new_entries, actions} = Turn.start_tool_execution(turn, [entry], 1, @context)

      assert new_turn.tool_invocations[1].status == :executing
      assert new_turn.tool_invocations[1].started_at != nil
      assert Enum.at(new_entries, 0).tool_status == :executing
      assert {:send_msf_command, "help"} in actions
      assert {:update_tool_status, 1, "executing", []} in actions
    end

    test "handles missing command argument" do
      tool_inv = make_tool_invocation("call_1", "msf_command", :approved, arguments: %{})
      entry = make_tool_entry(1, 1, "msf_command", :approved, arguments: %{})

      turn = make_turn(status: :executing_tools, tool_invocations: %{1 => tool_inv})

      {_new_turn, _new_entries, actions} = Turn.start_tool_execution(turn, [entry], 1, @context)

      # Should use empty string as default
      assert {:send_msf_command, ""} in actions
    end

    test "marks unknown tool as error" do
      tool_inv = make_tool_invocation("call_1", "unknown_tool", :approved)
      entry = make_tool_entry(1, 1, "unknown_tool", :approved)

      turn = make_turn(tool_invocations: %{1 => tool_inv})

      {new_turn, new_entries, actions} = Turn.start_tool_execution(turn, [entry], 1, @context)

      assert new_turn.tool_invocations[1].status == :error
      assert Enum.at(new_entries, 0).tool_status == :error

      assert {:update_tool_status, 1, "error", opts} =
               Enum.find(actions, &match?({:update_tool_status, _, "error", _}, &1))

      assert opts[:error_message] =~ "Unknown tool"
    end

    test "returns unchanged state for unknown entry_id" do
      turn = make_turn(tool_invocations: %{})

      {new_turn, new_entries, actions} = Turn.start_tool_execution(turn, [], 999, @context)

      assert new_turn == turn
      assert new_entries == []
      assert actions == []
    end
  end

  describe "complete_tool_execution/4" do
    test "completes executing tool and sets result_content on entry" do
      started_at = DateTime.add(DateTime.utc_now(), -1, :second)

      tool_inv =
        make_tool_invocation("call_1", "msf_command", :executing,
          command_id: "cmd-1",
          started_at: started_at
        )

      entry = make_tool_entry(1, 1, "msf_command", :executing)

      turn =
        make_turn(
          status: :executing_tools,
          tool_invocations: %{1 => tool_inv},
          command_to_tool: %{"cmd-1" => 1}
        )

      {new_turn, new_entries, actions} =
        Turn.complete_tool_execution(turn, [entry], "command output here", "cmd-1")

      assert new_turn.tool_invocations[1].status == :success

      # Verify entry has both status AND result_content updated
      completed_entry = Enum.at(new_entries, 0)
      assert completed_entry.tool_status == :success
      assert completed_entry.result_content == "command output here"

      assert {:update_tool_status, 1, "success", opts} =
               Enum.find(actions, &match?({:update_tool_status, _, "success", _}, &1))

      assert opts[:result_content] == "command output here"
      assert opts[:duration_ms] >= 0
      assert :reconcile in actions
    end

    test "returns no_executing_tool when no tool is executing" do
      turn = make_turn(tool_invocations: %{})

      assert :no_executing_tool = Turn.complete_tool_execution(turn, [], "output", nil)
    end
  end

  describe "complete_bash_tool/4" do
    test "completes bash tool and sets result_content on entry" do
      started_at = DateTime.add(DateTime.utc_now(), -1, :second)

      tool_inv =
        make_tool_invocation("call_1", "bash_command", :executing,
          command_id: "bash-cmd-1",
          started_at: started_at
        )

      entry = make_tool_entry(1, 1, "bash_command", :executing)

      turn =
        make_turn(
          status: :executing_tools,
          tool_invocations: %{1 => tool_inv},
          command_to_tool: %{"bash-cmd-1" => 1}
        )

      {new_turn, new_entries, actions} =
        Turn.complete_bash_tool(turn, [entry], "bash-cmd-1", "bash output\nwith lines")

      assert new_turn.tool_invocations[1].status == :success

      # Verify entry has both status AND result_content updated
      completed_entry = Enum.at(new_entries, 0)
      assert completed_entry.tool_status == :success
      assert completed_entry.result_content == "bash output\nwith lines"

      assert {:update_tool_status, 1, "success", opts} =
               Enum.find(actions, &match?({:update_tool_status, _, "success", _}, &1))

      assert opts[:result_content] == "bash output\nwith lines"
      assert opts[:duration_ms] >= 0
      assert :reconcile in actions
      assert :broadcast_chat_state in actions
    end

    test "returns no_executing_tool when command_id not found" do
      turn = make_turn(tool_invocations: %{}, command_to_tool: %{})

      assert :no_executing_tool = Turn.complete_bash_tool(turn, [], "unknown-id", "output")
    end
  end

  describe "error_bash_tool/4" do
    test "marks bash tool as error with error message" do
      started_at = DateTime.add(DateTime.utc_now(), -1, :second)

      tool_inv =
        make_tool_invocation("call_1", "bash_command", :executing,
          command_id: "bash-cmd-1",
          started_at: started_at
        )

      entry = make_tool_entry(1, 1, "bash_command", :executing)

      turn =
        make_turn(
          status: :executing_tools,
          tool_invocations: %{1 => tool_inv},
          command_to_tool: %{"bash-cmd-1" => 1}
        )

      {new_turn, new_entries, actions} =
        Turn.error_bash_tool(turn, [entry], "bash-cmd-1", "command not found")

      assert new_turn.tool_invocations[1].status == :error
      assert Enum.at(new_entries, 0).tool_status == :error

      assert {:update_tool_status, 1, "error", opts} =
               Enum.find(actions, &match?({:update_tool_status, _, "error", _}, &1))

      assert opts[:error_message] == "command not found"
      assert :reconcile in actions
    end

    test "handles nil started_at gracefully" do
      # Test the nil started_at branch
      tool_inv =
        make_tool_invocation("call_1", "bash_command", :executing,
          command_id: "bash-cmd-1",
          started_at: nil
        )

      entry = make_tool_entry(1, 1, "bash_command", :executing)

      turn =
        make_turn(
          status: :executing_tools,
          tool_invocations: %{1 => tool_inv},
          command_to_tool: %{"bash-cmd-1" => 1}
        )

      {new_turn, _new_entries, actions} =
        Turn.error_bash_tool(turn, [entry], "bash-cmd-1", "error message")

      assert new_turn.tool_invocations[1].status == :error

      assert {:update_tool_status, 1, "error", opts} =
               Enum.find(actions, &match?({:update_tool_status, _, "error", _}, &1))

      # Duration should be 0 when started_at is nil
      assert opts[:duration_ms] == 0
    end

    test "returns no_executing_tool when command_id not found" do
      turn = make_turn(tool_invocations: %{}, command_to_tool: %{})

      assert :no_executing_tool = Turn.error_bash_tool(turn, [], "unknown-id", "error")
    end
  end

  describe "record_command_id/3" do
    test "records command_id for existing tool" do
      tool_inv = make_tool_invocation("call_1", "msf_command", :executing)

      turn = make_turn(tool_invocations: %{1 => tool_inv})

      new_turn = Turn.record_command_id(turn, 1, "cmd-123")

      assert new_turn.tool_invocations[1].command_id == "cmd-123"
      assert new_turn.command_to_tool["cmd-123"] == 1
    end

    test "returns unchanged turn for unknown entry_id" do
      turn = make_turn(tool_invocations: %{})

      new_turn = Turn.record_command_id(turn, 999, "cmd-123")

      assert new_turn == turn
    end
  end

  describe "mark_tool_error/4" do
    test "marks tool as error" do
      tool_inv = make_tool_invocation("call_1", "msf_command", :executing)
      entry = make_tool_entry(1, 1, "msf_command", :executing)

      turn = make_turn(tool_invocations: %{1 => tool_inv})

      {new_turn, new_entries, actions} = Turn.mark_tool_error(turn, [entry], 1, :timeout)

      assert new_turn.tool_invocations[1].status == :error
      assert Enum.at(new_entries, 0).tool_status == :error

      assert {:update_tool_status, 1, "error", opts} =
               Enum.find(actions, &match?({:update_tool_status, _, "error", _}, &1))

      assert opts[:error_message] =~ "timeout"
    end

    test "returns unchanged state for unknown entry_id" do
      turn = make_turn(tool_invocations: %{})

      {new_turn, new_entries, actions} = Turn.mark_tool_error(turn, [], 999, :error)

      assert new_turn == turn
      assert new_entries == []
      assert actions == []
    end
  end

  # ===========================================================================
  # Handle Tool Call Tests
  # ===========================================================================

  describe "handle_tool_call/5" do
    test "creates tool invocation in non-autonomous mode" do
      turn = make_turn(status: :streaming, turn_id: "turn-123")
      stream = StreamState.new(1)
      entries = []

      tool_call = %LLMEvents.ToolCall{
        id: "call_abc",
        name: "msf_command",
        arguments: %{"command" => "search apache"}
      }

      context = %{track_id: 42, autonomous: false, current_prompt: "msf6 >"}

      {new_turn, new_stream, new_entries, actions} =
        Turn.handle_tool_call(turn, stream, entries, tool_call, context)

      assert new_stream.next_position == 2
      assert Map.has_key?(new_turn.tool_invocations, 1)
      assert new_turn.tool_invocations[1].status == :pending
      assert new_turn.tool_invocations[1].tool_call_id == "call_abc"

      assert [entry] = new_entries
      assert entry.entry_type == :tool_invocation
      assert entry.tool_status == :pending
      assert entry.tool_name == "msf_command"
      assert entry.console_prompt == "msf6 >"

      assert {:persist_tool_invocation, 42, "turn-123", 1, attrs} = Enum.at(actions, 0)
      assert attrs.status == "pending"
    end

    test "auto-approves tool in autonomous mode" do
      turn = make_turn(status: :streaming, turn_id: "turn-123")
      stream = StreamState.new(1)
      entries = []

      tool_call = %LLMEvents.ToolCall{
        id: "call_abc",
        name: "msf_command",
        arguments: %{}
      }

      context = %{track_id: 42, autonomous: true, current_prompt: "msf6 >"}

      {new_turn, _new_stream, new_entries, actions} =
        Turn.handle_tool_call(turn, stream, entries, tool_call, context)

      assert new_turn.tool_invocations[1].status == :approved
      assert [entry] = new_entries
      assert entry.tool_status == :approved

      assert {:persist_tool_invocation, 42, "turn-123", 1, attrs} = Enum.at(actions, 0)
      assert attrs.status == "approved"
    end

    # Tests for approval_required behavior
    test "auto-approves tool with approval_required: false in non-autonomous mode" do
      # Tools like list_hosts have approval_required: false and should
      # auto-approve even when not in autonomous mode
      turn = make_turn(status: :streaming, turn_id: "turn-123")
      stream = StreamState.new(1)
      entries = []

      tool_call = %LLMEvents.ToolCall{
        id: "call_abc",
        name: "list_hosts",
        arguments: %{}
      }

      context = %{track_id: 42, autonomous: false, current_prompt: "msf6 >"}

      {new_turn, _new_stream, new_entries, actions} =
        Turn.handle_tool_call(turn, stream, entries, tool_call, context)

      # Should be auto-approved because approval_required: false
      assert new_turn.tool_invocations[1].status == :approved
      assert [entry] = new_entries
      assert entry.tool_status == :approved

      assert {:persist_tool_invocation, 42, "turn-123", 1, attrs} = Enum.at(actions, 0)
      assert attrs.status == "approved"
    end

    test "auto-approves tool with approval_required: false in autonomous mode" do
      turn = make_turn(status: :streaming, turn_id: "turn-123")
      stream = StreamState.new(1)
      entries = []

      tool_call = %LLMEvents.ToolCall{
        id: "call_abc",
        name: "list_hosts",
        arguments: %{}
      }

      context = %{track_id: 42, autonomous: true, current_prompt: "msf6 >"}

      {new_turn, _new_stream, new_entries, actions} =
        Turn.handle_tool_call(turn, stream, entries, tool_call, context)

      # Should be auto-approved in both cases
      assert new_turn.tool_invocations[1].status == :approved
      assert [entry] = new_entries
      assert entry.tool_status == :approved

      assert {:persist_tool_invocation, 42, "turn-123", 1, attrs} = Enum.at(actions, 0)
      assert attrs.status == "approved"
    end

    test "requires approval for unknown tools in non-autonomous mode" do
      # Unknown tools should default to requiring approval for safety
      turn = make_turn(status: :streaming, turn_id: "turn-123")
      stream = StreamState.new(1)
      entries = []

      tool_call = %LLMEvents.ToolCall{
        id: "call_abc",
        name: "unknown_future_tool",
        arguments: %{}
      }

      context = %{track_id: 42, autonomous: false, current_prompt: "msf6 >"}

      {new_turn, _new_stream, new_entries, actions} =
        Turn.handle_tool_call(turn, stream, entries, tool_call, context)

      # Should require approval since tool is unknown (safe default)
      assert new_turn.tool_invocations[1].status == :pending
      assert [entry] = new_entries
      assert entry.tool_status == :pending

      assert {:persist_tool_invocation, 42, "turn-123", 1, attrs} = Enum.at(actions, 0)
      assert attrs.status == "pending"
    end
  end

  # ===========================================================================
  # Start Turn Tests
  # ===========================================================================

  describe "start_turn/5" do
    test "creates turn and returns actions" do
      stream = StreamState.new(1)
      entries = []
      track_id = 999
      context = %{track_id: track_id}

      {:ok, new_turn, new_stream, new_entries, actions} =
        Turn.start_turn(stream, entries, "Hello!", "gpt-4", context)

      assert new_turn.status == :pending
      assert new_turn.model == "gpt-4"
      assert new_stream.next_position == 2

      assert [entry] = new_entries
      assert entry.entry_type == :message
      assert entry.role == :user
      assert entry.content == "Hello!"

      assert {:create_turn, ^track_id, "gpt-4"} =
               Enum.find(actions, &match?({:create_turn, _, _}, &1))

      assert {:persist_message, _, nil, 1, _} =
               Enum.find(actions, &match?({:persist_message, _, _, _, _}, &1))

      assert {:start_llm, _request} = Enum.find(actions, &match?({:start_llm, _}, &1))
    end
  end

  # ===========================================================================
  # Reconcile with LLM continuation
  # ===========================================================================

  describe "reconcile/4 - LLM continuation" do
    test "starts next LLM request when all tools are terminal" do
      tool_inv = make_tool_invocation("call_1", "msf_command", :success)

      turn =
        make_turn(
          status: :executing_tools,
          model: "gpt-4",
          tool_invocations: %{1 => tool_inv}
        )

      console = make_console()
      track_id = 999
      context = %{track_id: track_id, model: "gpt-4", autonomous: false}

      {new_turn, _entries, actions} = Turn.reconcile(turn, console, [], context)

      assert new_turn.status == :pending
      assert new_turn.tool_invocations == %{}
      assert {:start_llm, _} = Enum.find(actions, &match?({:start_llm, _}, &1))
    end

    test "preserves chat entries when starting next LLM request" do
      # Regression test: start_llm_request was returning [] for entries,
      # which wiped out state.chat_entries when reconciling after tool completion
      tool_inv = make_tool_invocation("call_1", "msf_command", :success)

      turn =
        make_turn(
          status: :executing_tools,
          model: "gpt-4",
          tool_invocations: %{1 => tool_inv}
        )

      console = make_console()
      track_id = 999
      context = %{track_id: track_id, model: "gpt-4", autonomous: false}

      # Create existing entries that should be preserved
      existing_entries = [
        ChatEntry.user_prompt("entry-1", 1, "Hello!", DateTime.utc_now()),
        ChatEntry.assistant_response("entry-2", 2, "Hi there", DateTime.utc_now()),
        make_tool_entry(3, 3, "msf_command", :success)
      ]

      {_new_turn, returned_entries, _actions} =
        Turn.reconcile(turn, console, existing_entries, context)

      # Entries must be preserved, not wiped out
      assert length(returned_entries) == 3
      assert returned_entries == existing_entries
    end
  end

  # ===========================================================================
  # Approved Tools Execute While Others Pending
  # ===========================================================================

  describe "reconcile/4 - approved tools execute while others pending" do
    alias Msfailab.Tracks

    # Helper to create a track for memory tool tests
    defp create_track_for_memory_test do
      unique = System.unique_integer([:positive])

      {:ok, workspace} =
        Msfailab.Workspaces.create_workspace(%{slug: "test-#{unique}", name: "Test #{unique}"})

      {:ok, container} =
        Msfailab.Containers.create_container(workspace, %{
          slug: "container-#{unique}",
          name: "Container #{unique}",
          docker_image: "test:latest"
        })

      {:ok, track} =
        Tracks.create_track(container, %{
          name: "Track #{unique}",
          slug: "track-#{unique}"
        })

      track
    end

    test "executes approved parallel tools from :streaming status when others are pending" do
      # Bug: When LLM stream completes with tool_use, status is :streaming.
      # Approved parallel tools should execute immediately, even if some tools
      # need approval. Previously, should_execute_parallel_tools? only allowed
      # :pending_approval and :executing_tools, blocking execution from :streaming.

      track = create_track_for_memory_test()

      update_memory_inv =
        make_tool_invocation("call_1", "update_memory", :approved,
          arguments: %{"objective" => "Find the router"}
        )

      bash_inv =
        make_tool_invocation("call_2", "bash_command", :pending,
          arguments: %{"command" => "nmap 192.168.1.1"}
        )

      # Key: status is :streaming (as it would be when LLM stream completes)
      turn =
        make_turn(
          status: :streaming,
          model: "gpt-4",
          tool_invocations: %{
            1 => update_memory_inv,
            2 => bash_inv
          }
        )

      console = make_console()

      entries = [
        make_tool_entry(1, 1, "update_memory", :approved,
          tool_call_id: "call_1",
          arguments: %{"objective" => "Find the router"}
        ),
        make_tool_entry(2, 2, "bash_command", :pending,
          tool_call_id: "call_2",
          arguments: %{"command" => "nmap 192.168.1.1"}
        )
      ]

      context = %{
        track_id: track.id,
        model: "gpt-4",
        autonomous: false
      }

      # The approved update_memory should execute even from :streaming status
      result = Turn.reconcile(turn, console, entries, context)

      # Should return updated turn (memory tool executed synchronously)
      assert {new_turn, _entries, actions} = result

      # Tool should be marked as success
      assert new_turn.tool_invocations[1].status == :success

      # Memory should be persisted to DB (not passed through return value)
      updated_track = Tracks.get_track(track.id)
      assert updated_track.memory.objective == "Find the router"

      # Should have update_tool_status action with success
      assert Enum.any?(actions, fn
               {:update_tool_status, 1, "success", _} -> true
               _ -> false
             end)
    end

    test "executes approved parallel tools even when other tools are pending approval" do
      # Set up: update_memory is approved (doesn't need approval)
      #         bash_command is pending (needs approval)

      track = create_track_for_memory_test()

      update_memory_inv =
        make_tool_invocation("call_1", "update_memory", :approved,
          arguments: %{"objective" => "Find the router"}
        )

      bash_inv =
        make_tool_invocation("call_2", "bash_command", :pending,
          arguments: %{"command" => "nmap 192.168.1.1"}
        )

      turn =
        make_turn(
          status: :executing_tools,
          model: "gpt-4",
          tool_invocations: %{
            1 => update_memory_inv,
            2 => bash_inv
          }
        )

      console = make_console()

      entries = [
        make_tool_entry(1, 1, "update_memory", :approved,
          tool_call_id: "call_1",
          arguments: %{"objective" => "Find the router"}
        ),
        make_tool_entry(2, 2, "bash_command", :pending,
          tool_call_id: "call_2",
          arguments: %{"command" => "nmap 192.168.1.1"}
        )
      ]

      context = %{
        track_id: track.id,
        model: "gpt-4",
        autonomous: false
      }

      # The approved update_memory should execute even though bash_command is pending
      result = Turn.reconcile(turn, console, entries, context)

      # Should return updated turn (memory tool executed synchronously)
      assert {new_turn, _entries, actions} = result

      # Tool should be marked as success
      assert new_turn.tool_invocations[1].status == :success

      # Memory should be persisted to DB
      updated_track = Tracks.get_track(track.id)
      assert updated_track.memory.objective == "Find the router"

      # Should have update_tool_status action with success
      assert Enum.any?(actions, fn
               {:update_tool_status, 1, "success", _} -> true
               _ -> false
             end)
    end
  end

  # ===========================================================================
  # Memory Tool Accumulation Tests
  # ===========================================================================

  describe "reconcile/4 - memory tool accumulation" do
    alias Msfailab.Tracks

    # Memory tools now have :memory mutex and execute sequentially,
    # which ensures they see each other's DB writes. This test verifies
    # the final memory state after all tools complete.

    # Helper to create a track for memory tool tests
    defp create_track_for_accumulation_test do
      unique = System.unique_integer([:positive])

      {:ok, workspace} =
        Msfailab.Workspaces.create_workspace(%{slug: "test-#{unique}", name: "Test #{unique}"})

      {:ok, container} =
        Msfailab.Containers.create_container(workspace, %{
          slug: "container-#{unique}",
          name: "Container #{unique}",
          docker_image: "test:latest"
        })

      {:ok, track} =
        Tracks.create_track(container, %{
          name: "Track #{unique}",
          slug: "track-#{unique}"
        })

      track
    end

    test "accumulates memory state across multiple parallel memory tools" do
      track = create_track_for_accumulation_test()

      # Set up turn with update_memory + 2 add_task tools, all approved
      update_memory_inv =
        make_tool_invocation("call_1", "update_memory", :approved,
          arguments: %{"objective" => "Find the router", "focus" => "Network scan"}
        )

      add_task_inv_1 =
        make_tool_invocation("call_2", "add_task", :approved,
          arguments: %{"content" => "Run port scan"}
        )

      add_task_inv_2 =
        make_tool_invocation("call_3", "add_task", :approved,
          arguments: %{"content" => "Check web interface"}
        )

      turn =
        make_turn(
          status: :executing_tools,
          model: "gpt-4",
          tool_invocations: %{
            1 => update_memory_inv,
            2 => add_task_inv_1,
            3 => add_task_inv_2
          }
        )

      console = make_console()

      entries = [
        make_tool_entry(1, 1, "update_memory", :approved,
          tool_call_id: "call_1",
          arguments: %{"objective" => "Find the router", "focus" => "Network scan"}
        ),
        make_tool_entry(2, 2, "add_task", :approved,
          tool_call_id: "call_2",
          arguments: %{"content" => "Run port scan"}
        ),
        make_tool_entry(3, 3, "add_task", :approved,
          tool_call_id: "call_3",
          arguments: %{"content" => "Check web interface"}
        )
      ]

      context = %{
        track_id: track.id,
        model: "gpt-4",
        autonomous: false
      }

      # Execute reconcile - should process all three memory tools
      result = Turn.reconcile(turn, console, entries, context)

      # Should return updated turn (memory persisted to DB)
      assert {new_turn, _entries, _actions} = result

      # All tools should be marked as success
      assert new_turn.tool_invocations[1].status == :success
      assert new_turn.tool_invocations[2].status == :success
      assert new_turn.tool_invocations[3].status == :success

      # The final memory in DB should have ACCUMULATED all changes:
      # - objective and focus from update_memory
      # - BOTH tasks from add_task calls
      updated_track = Tracks.get_track(track.id)
      final_memory = updated_track.memory

      assert final_memory.objective == "Find the router"
      assert final_memory.focus == "Network scan"
      assert length(final_memory.tasks) == 2

      task_contents = Enum.map(final_memory.tasks, & &1.content)
      assert "Run port scan" in task_contents
      assert "Check web interface" in task_contents
    end
  end
end
