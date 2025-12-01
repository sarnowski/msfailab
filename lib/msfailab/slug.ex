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

defmodule Msfailab.Slug do
  @moduledoc """
  Utilities for generating and validating slugs and names.

  Slugs are used for URLs and must be compatible with Linux usernames:
  - 1-32 characters
  - Must start with a lowercase letter
  - Can contain lowercase letters, digits, and hyphens
  - No consecutive hyphens
  - Cannot end with a hyphen

  Names are user-facing display strings:
  - 1-100 characters
  - Can contain letters, digits, spaces, and hyphens
  - No leading/trailing whitespace
  - No consecutive spaces
  """

  import Ecto.Changeset

  @max_slug_length 32
  @max_name_length 100

  # Slug: starts with letter, optional alphanumerics, then optional groups of hyphen + alphanumerics
  # This ensures: no consecutive hyphens, no trailing hyphens, must start with letter
  @slug_regex ~r/^[a-z]$|^[a-z][a-z0-9]*(-[a-z0-9]+)*$/

  # Name: letters, digits, spaces, hyphens only
  @name_regex ~r/^[A-Za-z0-9 -]+$/

  @doc """
  Generates a valid slug from a name string.

  ## Examples

      iex> Msfailab.Slug.generate("ACME Corp Pentest")
      "acme-corp-pentest"

      iex> Msfailab.Slug.generate("2024 Review")
      "n2024-review"

      iex> Msfailab.Slug.generate("Hello   World")
      "hello-world"

  """
  @spec generate(String.t()) :: String.t()
  def generate(name) when is_binary(name) do
    slug =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.replace(~r/-+/, "-")
      |> String.trim("-")

    # Prepend 'n' if slug starts with a digit
    slug =
      if slug != "" and String.match?(slug, ~r/^[0-9]/) do
        "n" <> slug
      else
        slug
      end

    # Truncate to max length, ensuring no trailing hyphen
    slug
    |> truncate_slug(@max_slug_length)
  end

  def generate(_), do: ""

  @doc """
  Checks if a slug is valid.

  ## Examples

      iex> Msfailab.Slug.valid_slug?("my-project")
      true

      iex> Msfailab.Slug.valid_slug?("2024-test")
      false

      iex> Msfailab.Slug.valid_slug?("test--name")
      false

  """
  @spec valid_slug?(String.t()) :: boolean()
  def valid_slug?(slug) when is_binary(slug) do
    byte_size(slug) >= 1 and
      byte_size(slug) <= @max_slug_length and
      String.match?(slug, @slug_regex)
  end

  def valid_slug?(_), do: false

  @doc """
  Checks if a name is valid.

  ## Examples

      iex> Msfailab.Slug.valid_name?("My Project")
      true

      iex> Msfailab.Slug.valid_name?("  Trimmed  ")
      false

      iex> Msfailab.Slug.valid_name?("Has  Double  Spaces")
      false

  """
  @spec valid_name?(String.t()) :: boolean()
  def valid_name?(name) when is_binary(name) do
    trimmed = String.trim(name)

    byte_size(name) >= 1 and
      byte_size(name) <= @max_name_length and
      name == trimmed and
      String.match?(name, @name_regex) and
      not String.contains?(name, "  ")
  end

  def valid_name?(_), do: false

  @doc """
  Validates the slug field in a changeset.
  """
  @spec validate_slug(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate_slug(changeset, field) do
    changeset
    |> validate_required([field])
    |> validate_length(field, min: 1, max: @max_slug_length)
    |> validate_format(field, @slug_regex,
      message:
        "must start with a letter, contain only lowercase letters, numbers, and hyphens, with no consecutive or trailing hyphens"
    )
  end

  @doc """
  Validates the name field in a changeset.
  """
  @spec validate_name(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate_name(changeset, field) do
    changeset
    |> validate_required([field])
    |> validate_length(field, min: 1, max: @max_name_length)
    |> validate_format(field, @name_regex,
      message: "can only contain letters, numbers, spaces, and hyphens"
    )
    |> validate_no_surrounding_whitespace(field)
    |> validate_no_consecutive_spaces(field)
  end

  defp validate_no_surrounding_whitespace(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      if value == String.trim(value) do
        []
      else
        [{field, "must not have leading or trailing whitespace"}]
      end
    end)
  end

  defp validate_no_consecutive_spaces(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      if String.contains?(value, "  ") do
        [{field, "must not contain consecutive spaces"}]
      else
        []
      end
    end)
  end

  defp truncate_slug(slug, max_length) when byte_size(slug) <= max_length, do: slug

  defp truncate_slug(slug, max_length) do
    slug
    |> String.slice(0, max_length)
    |> String.trim_trailing("-")
  end
end
