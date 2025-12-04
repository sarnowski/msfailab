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

defmodule MsfailabWeb.WorkspaceLive.CommandHandlerTest do
  use ExUnit.Case, async: true

  alias MsfailabWeb.WorkspaceLive.CommandHandler

  describe "format_msf_error/1" do
    test "formats container_not_running error" do
      assert CommandHandler.format_msf_error(:container_not_running) == "Container is not running"
    end

    test "formats console_starting error" do
      assert CommandHandler.format_msf_error(:console_starting) ==
               "Console is still starting up, please wait"
    end

    test "formats console_busy error" do
      assert CommandHandler.format_msf_error(:console_busy) ==
               "Console is busy processing a command"
    end

    test "formats console_offline error" do
      assert CommandHandler.format_msf_error(:console_offline) == "Console is offline"
    end

    test "formats console_not_registered error" do
      assert CommandHandler.format_msf_error(:console_not_registered) ==
               "Console is not registered for this track"
    end

    test "formats unknown errors with inspect" do
      assert CommandHandler.format_msf_error(:unknown_error) == "Command failed: :unknown_error"

      assert CommandHandler.format_msf_error({:timeout, 5000}) ==
               "Command failed: {:timeout, 5000}"
    end
  end

  describe "format_chat_error/1" do
    test "formats not_found error" do
      assert CommandHandler.format_chat_error(:not_found) == "Track server not found"
    end

    test "formats unknown errors with inspect" do
      assert CommandHandler.format_chat_error(:some_error) ==
               "Failed to send message: :some_error"

      assert CommandHandler.format_chat_error({:timeout, 10_000}) ==
               "Failed to send message: {:timeout, 10000}"
    end
  end

  describe "no_track_error/0" do
    test "returns the no track error message" do
      assert CommandHandler.no_track_error() == "No track selected"
    end
  end
end
