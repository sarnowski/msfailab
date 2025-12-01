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

defmodule Msfailab.SlugTest do
  use ExUnit.Case, async: true

  alias Msfailab.Slug

  describe "generate/1" do
    test "converts name to lowercase" do
      assert Slug.generate("ACME Corp") == "acme-corp"
    end

    test "replaces spaces with hyphens" do
      assert Slug.generate("My Project") == "my-project"
    end

    test "preserves numbers" do
      assert Slug.generate("Test 123") == "test-123"
    end

    test "prepends 'n' when starting with digit" do
      assert Slug.generate("2024 Review") == "n2024-review"
    end

    test "handles single letter" do
      assert Slug.generate("A") == "a"
    end

    test "collapses multiple spaces" do
      assert Slug.generate("Hello   World") == "hello-world"
    end

    test "preserves hyphens" do
      assert Slug.generate("Red-Team Exercise") == "red-team-exercise"
    end

    test "trims whitespace" do
      assert Slug.generate("  Trimmed Name  ") == "trimmed-name"
    end

    test "removes special characters" do
      assert Slug.generate("Special!@#Chars") == "specialchars"
    end

    test "truncates to 32 characters" do
      result = Slug.generate("Very Long Workspace Name That Exceeds The Limit")
      assert byte_size(result) <= 32
      assert result == "very-long-workspace-name-that-ex"
    end

    test "removes trailing hyphen after truncation" do
      # "very-long-name-that-ends-at-hyph" is 32 chars, no trailing hyphen
      result = Slug.generate("Very Long Name That Ends At Hyphen")
      assert byte_size(result) <= 32
      assert not String.ends_with?(result, "-")
    end

    test "handles empty string" do
      assert Slug.generate("") == ""
    end

    test "handles nil" do
      assert Slug.generate(nil) == ""
    end

    test "handles only numbers" do
      assert Slug.generate("12345") == "n12345"
    end

    test "collapses consecutive hyphens" do
      assert Slug.generate("hello---world") == "hello-world"
    end
  end

  describe "valid_slug?/1" do
    test "accepts valid single letter" do
      assert Slug.valid_slug?("a")
    end

    test "accepts valid slug with letters only" do
      assert Slug.valid_slug?("myproject")
    end

    test "accepts valid slug with letters and numbers" do
      assert Slug.valid_slug?("test123")
    end

    test "accepts valid slug with hyphens" do
      assert Slug.valid_slug?("my-project")
    end

    test "accepts valid slug ending with number" do
      assert Slug.valid_slug?("project-2024")
    end

    test "rejects slug starting with number" do
      refute Slug.valid_slug?("2024-test")
    end

    test "rejects slug starting with hyphen" do
      refute Slug.valid_slug?("-test")
    end

    test "rejects slug ending with hyphen" do
      refute Slug.valid_slug?("test-")
    end

    test "rejects slug with consecutive hyphens" do
      refute Slug.valid_slug?("test--name")
    end

    test "rejects slug with uppercase" do
      refute Slug.valid_slug?("MyProject")
    end

    test "rejects slug with underscore" do
      refute Slug.valid_slug?("my_project")
    end

    test "rejects slug with spaces" do
      refute Slug.valid_slug?("my project")
    end

    test "rejects empty string" do
      refute Slug.valid_slug?("")
    end

    test "rejects slug exceeding 32 characters" do
      refute Slug.valid_slug?("abcdefghijklmnopqrstuvwxyz1234567")
    end

    test "accepts slug at exactly 32 characters" do
      assert Slug.valid_slug?("abcdefghijklmnopqrstuvwxyz123456")
    end

    test "rejects nil" do
      refute Slug.valid_slug?(nil)
    end
  end

  describe "valid_name?/1" do
    test "accepts valid name with letters only" do
      assert Slug.valid_name?("MyProject")
    end

    test "accepts valid name with spaces" do
      assert Slug.valid_name?("My Project")
    end

    test "accepts valid name with numbers" do
      assert Slug.valid_name?("Project 2024")
    end

    test "accepts valid name with hyphens" do
      assert Slug.valid_name?("Red-Team Exercise")
    end

    test "accepts single character" do
      assert Slug.valid_name?("A")
    end

    test "rejects name with leading whitespace" do
      refute Slug.valid_name?("  My Project")
    end

    test "rejects name with trailing whitespace" do
      refute Slug.valid_name?("My Project  ")
    end

    test "rejects name with consecutive spaces" do
      refute Slug.valid_name?("My  Project")
    end

    test "rejects name with special characters" do
      refute Slug.valid_name?("My Project!")
    end

    test "rejects name with underscore" do
      refute Slug.valid_name?("my_project")
    end

    test "rejects empty string" do
      refute Slug.valid_name?("")
    end

    test "rejects nil" do
      refute Slug.valid_name?(nil)
    end

    test "accepts name at exactly 100 characters" do
      name = String.duplicate("A", 100)
      assert Slug.valid_name?(name)
    end

    test "rejects name exceeding 100 characters" do
      name = String.duplicate("A", 101)
      refute Slug.valid_name?(name)
    end
  end
end
