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

defmodule Msfailab.LLMTest do
  use ExUnit.Case, async: true

  alias Msfailab.LLM

  describe "get_system_prompt/0" do
    test "returns the system prompt content" do
      assert {:ok, prompt} = LLM.get_system_prompt()
      assert is_binary(prompt)
      assert String.length(prompt) > 0
    end

    test "system prompt contains expected sections" do
      {:ok, prompt} = LLM.get_system_prompt()

      # System prompt should contain instructions for the AI
      assert String.contains?(prompt, "Metasploit") or String.contains?(prompt, "security")
    end
  end

  describe "list_models/0" do
    test "returns empty list when registry not running" do
      # When registry is not started, should return empty list
      assert LLM.list_models() == []
    end
  end
end
