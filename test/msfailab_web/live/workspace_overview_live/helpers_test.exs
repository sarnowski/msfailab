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

defmodule MsfailabWeb.WorkspaceOverviewLive.HelpersTest do
  use Msfailab.DataCase, async: true

  alias Ecto.Changeset
  alias Msfailab.Workspaces
  alias Msfailab.Workspaces.Workspace
  alias MsfailabWeb.WorkspaceOverviewLive.Helpers

  describe "slug_helper/2" do
    test "returns full URL with slug when slug is valid" do
      field = %{value: "my-workspace", errors: []}
      base_url = "https://example.com"

      assert Helpers.slug_helper(field, base_url) == "https://example.com/my-workspace"
    end

    test "returns placeholder when slug is empty string" do
      field = %{value: "", errors: []}
      base_url = "https://example.com"

      assert Helpers.slug_helper(field, base_url) == "https://example.com/your-slug"
    end

    test "returns placeholder when slug is nil" do
      field = %{value: nil, errors: []}
      base_url = "https://example.com"

      assert Helpers.slug_helper(field, base_url) == "https://example.com/your-slug"
    end

    test "returns placeholder when field has errors" do
      field = %{value: "valid-slug", errors: [slug: {"is invalid", []}]}
      base_url = "https://example.com"

      assert Helpers.slug_helper(field, base_url) == "https://example.com/your-slug"
    end

    test "returns placeholder when slug is empty and has errors" do
      field = %{value: "", errors: [slug: {"can't be blank", []}]}
      base_url = "https://example.com"

      assert Helpers.slug_helper(field, base_url) == "https://example.com/your-slug"
    end

    test "works with different base URLs" do
      field = %{value: "test-slug", errors: []}

      assert Helpers.slug_helper(field, "http://localhost:4000") ==
               "http://localhost:4000/test-slug"

      assert Helpers.slug_helper(field, "https://app.example.org") ==
               "https://app.example.org/test-slug"
    end
  end

  describe "validate_slug_uniqueness/1" do
    test "returns unchanged changeset when slug does not exist" do
      changeset = Changeset.change(%Workspace{}, %{name: "Test", slug: "unique-slug-12345"})

      result = Helpers.validate_slug_uniqueness(changeset)

      assert result.errors == []
    end

    test "adds error when slug already exists" do
      # Create a workspace first
      {:ok, _workspace} =
        Workspaces.create_workspace(%{name: "Existing", slug: "existing-slug"})

      changeset = Changeset.change(%Workspace{}, %{name: "New", slug: "existing-slug"})

      result = Helpers.validate_slug_uniqueness(changeset)

      assert {:slug, {"is already taken", []}} in result.errors
    end

    test "returns unchanged changeset when slug is nil" do
      changeset = Changeset.change(%Workspace{}, %{name: "Test", slug: nil})

      result = Helpers.validate_slug_uniqueness(changeset)

      assert result.errors == []
    end

    test "returns unchanged changeset when slug is empty" do
      # Empty string after get_field would be falsy in the if condition
      changeset = Changeset.change(%Workspace{}, %{name: "Test"})

      result = Helpers.validate_slug_uniqueness(changeset)

      assert result.errors == []
    end
  end
end
