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

defmodule MsfailabWeb.WorkspaceLive.ModelSelectorTest do
  use ExUnit.Case, async: true

  alias MsfailabWeb.WorkspaceLive.ModelSelector

  describe "select_model_for_track/2" do
    test "returns nil when track is nil" do
      assert ModelSelector.select_model_for_track(nil, [%{name: "model1"}]) == nil
    end

    test "returns track's current_model when set" do
      track = %{current_model: "claude-3-haiku"}
      available = [%{name: "claude-3-opus"}, %{name: "claude-3-haiku"}]

      assert ModelSelector.select_model_for_track(track, available) == "claude-3-haiku"
    end

    test "returns first available model when current_model is nil" do
      track = %{current_model: nil}
      available = [%{name: "claude-3-opus"}, %{name: "claude-3-haiku"}]

      assert ModelSelector.select_model_for_track(track, available) == "claude-3-opus"
    end

    test "returns nil when current_model is nil and no models available" do
      track = %{current_model: nil}

      assert ModelSelector.select_model_for_track(track, []) == nil
    end
  end

  describe "first_model_name/1" do
    test "returns nil for empty list" do
      assert ModelSelector.first_model_name([]) == nil
    end

    test "returns name of first model" do
      models = [%{name: "first"}, %{name: "second"}]
      assert ModelSelector.first_model_name(models) == "first"
    end

    test "returns name when only one model" do
      models = [%{name: "only-model"}]
      assert ModelSelector.first_model_name(models) == "only-model"
    end
  end
end
