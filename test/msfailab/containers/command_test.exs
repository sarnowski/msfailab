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

defmodule Msfailab.Containers.CommandTest do
  use ExUnit.Case, async: true

  alias Msfailab.Containers.Command

  describe "new/2" do
    test "creates a metasploit command in running state" do
      cmd = Command.new(:metasploit, "db_status")

      assert cmd.type == :metasploit
      assert cmd.command == "db_status"
      assert cmd.status == :running
      assert cmd.output == ""
      assert cmd.prompt == ""
      assert cmd.exit_code == nil
      assert cmd.error == nil
      assert %DateTime{} = cmd.started_at
      assert is_binary(cmd.id)
      assert String.length(cmd.id) == 16
    end

    test "creates a bash command in running state" do
      cmd = Command.new(:bash, "ls -la")

      assert cmd.type == :bash
      assert cmd.command == "ls -la"
      assert cmd.status == :running
    end

    test "generates unique IDs for each command" do
      cmd1 = Command.new(:bash, "ls")
      cmd2 = Command.new(:bash, "ls")

      assert cmd1.id != cmd2.id
    end
  end

  describe "append_output/2" do
    test "appends output to empty buffer" do
      cmd =
        Command.new(:bash, "ls")
        |> Command.append_output("file1.txt\n")

      assert cmd.output == "file1.txt\n"
    end

    test "appends output to existing buffer" do
      cmd =
        Command.new(:bash, "ls")
        |> Command.append_output("file1.txt\n")
        |> Command.append_output("file2.txt\n")

      assert cmd.output == "file1.txt\nfile2.txt\n"
    end

    test "handles empty output" do
      cmd =
        Command.new(:bash, "ls")
        |> Command.append_output("")

      assert cmd.output == ""
    end
  end

  describe "set_prompt/2" do
    test "sets the prompt" do
      cmd =
        Command.new(:metasploit, "use exploit/multi/handler")
        |> Command.set_prompt("msf6 exploit(multi/handler) > ")

      assert cmd.prompt == "msf6 exploit(multi/handler) > "
    end

    test "replaces existing prompt" do
      cmd =
        Command.new(:metasploit, "help")
        |> Command.set_prompt("msf6 > ")
        |> Command.set_prompt("msf6 auxiliary(scanner) > ")

      assert cmd.prompt == "msf6 auxiliary(scanner) > "
    end
  end

  describe "finish/2" do
    test "marks command as finished without exit code" do
      cmd =
        Command.new(:metasploit, "help")
        |> Command.finish()

      assert cmd.status == :finished
      assert cmd.exit_code == nil
    end

    test "marks command as finished with exit code" do
      cmd =
        Command.new(:bash, "ls")
        |> Command.finish(exit_code: 0)

      assert cmd.status == :finished
      assert cmd.exit_code == 0
    end

    test "marks command as finished with non-zero exit code" do
      cmd =
        Command.new(:bash, "false")
        |> Command.finish(exit_code: 1)

      assert cmd.status == :finished
      assert cmd.exit_code == 1
    end
  end

  describe "error/2" do
    test "marks command as errored with reason" do
      cmd =
        Command.new(:bash, "ls")
        |> Command.error(:container_stopped)

      assert cmd.status == :error
      assert cmd.error == :container_stopped
    end

    test "marks command as errored with string reason" do
      cmd =
        Command.new(:metasploit, "help")
        |> Command.error("connection timeout")

      assert cmd.status == :error
      assert cmd.error == "connection timeout"
    end
  end

  describe "running?/1" do
    test "returns true for running command" do
      cmd = Command.new(:bash, "ls")
      assert Command.running?(cmd)
    end

    test "returns false for finished command" do
      cmd =
        Command.new(:bash, "ls")
        |> Command.finish(exit_code: 0)

      refute Command.running?(cmd)
    end

    test "returns false for errored command" do
      cmd =
        Command.new(:bash, "ls")
        |> Command.error(:timeout)

      refute Command.running?(cmd)
    end
  end
end
