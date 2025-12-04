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

defmodule MsfailabWeb.Console.PromptFormatter do
  @moduledoc """
  Pure functions for parsing and formatting Metasploit prompts.

  Extracts the tokenization state machine from Console module for testability.
  This module handles:
  - Parsing prompts into tokens (msf prefix, parenthesized content, plain text)
  - Classifying tokens for styling
  """

  @type token :: {:msf, String.t()} | {:paren_content, String.t()} | {:text, String.t()}

  @doc """
  Parses a Metasploit prompt into classified tokens.

  ## Token Types

  - `{:msf, "msf"}` - The "msf" prefix (will be underlined)
  - `{:paren_content, "path"}` - Content inside parentheses (will be colored)
  - `{:text, "text"}` - Plain text (escaped but not styled)

  ## Examples

      iex> PromptFormatter.parse_prompt_tokens("msf6 > ")
      [{:msf, "msf"}, {:text, "6 > "}]

      iex> PromptFormatter.parse_prompt_tokens("msf6 exploit(unix/http/foo) > ")
      [{:msf, "msf"}, {:text, "6 exploit"}, {:text, "("}, {:paren_content, "unix/http/foo"}, {:text, ") > "}]

  """
  @spec parse_prompt_tokens(String.t()) :: [token()]
  def parse_prompt_tokens(prompt) do
    ~r/(msf)|(\()|(\))|([^()]+)/
    |> Regex.scan(prompt, capture: :all_but_first)
    |> List.flatten()
    |> Enum.reject(&(&1 == ""))
    |> classify_tokens([])
  end

  @doc """
  Classifies a list of raw token strings into typed tokens.

  Uses a state machine to track when we're inside parentheses.

  ## Examples

      iex> PromptFormatter.classify_tokens(["msf", "6 > "], [])
      [{:msf, "msf"}, {:text, "6 > "}]

      iex> PromptFormatter.classify_tokens(["(", "path", ")"], [])
      [{:text, "("}, {:paren_content, "path"}, {:text, ")"}]

  """
  @spec classify_tokens([String.t()], [token()]) :: [token()]
  def classify_tokens([], acc), do: Enum.reverse(acc)
  def classify_tokens(["msf" | rest], acc), do: classify_tokens(rest, [{:msf, "msf"} | acc])
  def classify_tokens(["(" | rest], acc), do: classify_paren_content(rest, acc)
  def classify_tokens([text | rest], acc), do: classify_tokens(rest, [{:text, text} | acc])

  @doc """
  Processes tokens inside parentheses.

  Content before the closing paren is marked as paren_content.
  Parentheses themselves are marked as plain text.

  ## Examples

      iex> PromptFormatter.classify_paren_content(["path", ")"], [])
      [{:text, "("}, {:paren_content, "path"}, {:text, ")"}]

      iex> PromptFormatter.classify_paren_content([")"], [])
      [{:text, ")"}]

  """
  @spec classify_paren_content([String.t()], [token()]) :: [token()]
  def classify_paren_content([], acc), do: Enum.reverse(acc)

  def classify_paren_content([")" | rest], acc),
    do: classify_tokens(rest, [{:text, ")"} | acc])

  def classify_paren_content([content | rest], acc),
    do: classify_paren_content(rest, [{:paren_content, content}, {:text, "("} | acc])

  @doc """
  Renders a token to HTML.

  ## Examples

      iex> PromptFormatter.render_token({:msf, "msf"}, &Phoenix.HTML.html_escape/1)
      "<u>msf</u>"

      iex> PromptFormatter.render_token({:paren_content, "path"}, &Phoenix.HTML.html_escape/1)
      ~s(<span class="text-error">path</span>)

      iex> PromptFormatter.render_token({:text, ">"}, fn t -> {:safe, [?&, ?g, ?t, ?;]} end)
      "&gt;"

  """
  @spec render_token(token(), (String.t() -> Phoenix.HTML.safe())) :: String.t()
  def render_token({:msf, text}, escape_fn) do
    "<u>#{safe_to_string(escape_fn.(text))}</u>"
  end

  def render_token({:paren_content, text}, escape_fn) do
    ~s(<span class="text-error">#{safe_to_string(escape_fn.(text))}</span>)
  end

  def render_token({:text, text}, escape_fn) do
    safe_to_string(escape_fn.(text))
  end

  defp safe_to_string({:safe, iodata}), do: IO.iodata_to_binary(iodata)
end
