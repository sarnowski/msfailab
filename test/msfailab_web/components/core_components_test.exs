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

defmodule MsfailabWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  alias MsfailabWeb.CoreComponents

  describe "translate_error/1" do
    test "translates simple error message" do
      result = CoreComponents.translate_error({"can't be blank", []})

      assert result == "can't be blank"
    end

    test "translates error message with interpolation" do
      result = CoreComponents.translate_error({"is invalid", [validation: :format]})

      assert result == "is invalid"
    end

    test "translates error message with count for pluralization" do
      result = CoreComponents.translate_error({"should be %{count} character(s)", [count: 5]})

      assert result =~ "5"
    end

    test "handles error with count equal to 1" do
      result = CoreComponents.translate_error({"should be %{count} character(s)", [count: 1]})

      assert result =~ "1"
    end
  end

  describe "translate_errors/2" do
    test "translates errors for specific field" do
      errors = [
        name: {"can't be blank", []},
        email: {"is invalid", []},
        name: {"is too short", []}
      ]

      result = CoreComponents.translate_errors(errors, :name)

      assert length(result) == 2
      assert "can't be blank" in result
      assert "is too short" in result
    end

    test "returns empty list when field has no errors" do
      errors = [email: {"is invalid", []}]

      result = CoreComponents.translate_errors(errors, :name)

      assert result == []
    end

    test "returns empty list for empty errors" do
      result = CoreComponents.translate_errors([], :name)

      assert result == []
    end
  end
end
