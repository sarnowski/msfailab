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

defmodule MsfailabWeb.Console do
  alias MsfailabWeb.Console.PromptFormatter

  @moduledoc """
  Renders Metasploit console output with syntax highlighting.

  Provides two main rendering functions:
  - `to_html/1` - Colorizes output lines based on MSF prefix symbols
  - `format_prompt/1` - Formats MSF prompts with proper styling

  ## Prompt Styling
  MSF prompts follow this pattern: `msf6 exploit(unix/http/foo) > `
  - "msf" prefix is underlined
  - Text in parentheses is colored red
  - The `>` and version numbers are normal
  - Everything is rendered in bold

  ## Line Marker Styling
  Only the marker itself is colored, not the entire line:
  - `[*]` → Cyan (status/info)
  - `[+]` → Green (success)
  - `[-]` → Red (error)
  - `[!]` → Yellow (warning)
  """

  @doc """
  Converts console text to HTML with Metasploit symbol colorization.

  Only the prefix markers are colored, the rest of the line is plain.
  Returns a Phoenix.HTML.safe() tuple that can be directly rendered in templates.

  ## Examples

      iex> MsfailabWeb.Console.to_html("[+] Success!")
      {:safe, "<span class=\\"text-success\\">[+]</span> Success!"}

      iex> MsfailabWeb.Console.to_html("[-] Failed")
      {:safe, "<span class=\\"text-error\\">[-]</span> Failed"}

  """
  # Safe: All user text content is escaped via Phoenix.HTML.html_escape/1 in
  # escape/1. Only our generated span tags and CSS classes are unescaped.
  # sobelow_skip ["XSS.Raw"]
  @spec to_html(String.t()) :: Phoenix.HTML.safe()
  def to_html(text) when is_binary(text) do
    html =
      text
      |> String.split("\n")
      |> Enum.map_join("\n", &colorize_line/1)

    Phoenix.HTML.raw(html)
  end

  @doc """
  Formats an MSF prompt string with proper styling.

  Returns HTML with:
  - "msf" underlined
  - Module path in parentheses colored red
  - Everything bold

  ## Examples

      iex> MsfailabWeb.Console.format_prompt("msf6 > ")
      {:safe, "<strong><u>msf</u>6 &gt; </strong>"}

      iex> MsfailabWeb.Console.format_prompt("msf6 exploit(unix/http/foo) > ")
      {:safe, "<strong><u>msf</u>6 exploit<span class=\\"text-error\\">(unix/http/foo)</span> &gt; </strong>"}

  """
  # sobelow_skip ["XSS.Raw"]
  @spec format_prompt(String.t()) :: Phoenix.HTML.safe()
  def format_prompt(prompt) when is_binary(prompt) do
    html = format_prompt_parts(prompt)
    Phoenix.HTML.raw(html)
  end

  @doc """
  Renders an MSF console command line (prompt + command).

  - Prompt follows MSF styling (underlined "msf", red parentheses, bold)
  - Command is bold

  ## Examples

      iex> MsfailabWeb.Console.render_console_command("msf6 > ", "help")
      {:safe, "<strong><u>msf</u>6 &gt; </strong><strong>help</strong>"}

  """
  # sobelow_skip ["XSS.Raw"]
  @spec render_console_command(String.t(), String.t()) :: Phoenix.HTML.safe()
  def render_console_command(prompt, command) when is_binary(prompt) and is_binary(command) do
    Phoenix.HTML.raw(console_command_html(prompt, command))
  end

  @doc """
  Renders a bash command line (# prompt + command).

  - Prompt is bold "#"
  - Command is bold

  ## Examples

      iex> MsfailabWeb.Console.render_bash_command("ls -la")
      {:safe, "<strong># ls -la</strong>"}

  """
  # sobelow_skip ["XSS.Raw"]
  @spec render_bash_command(String.t()) :: Phoenix.HTML.safe()
  def render_bash_command(command) when is_binary(command) do
    Phoenix.HTML.raw(bash_command_html(command))
  end

  @doc """
  Renders complete MSF console output: prompt + command + output.

  - Prompt follows MSF styling (underlined "msf", red parentheses, bold)
  - Command is bold
  - Output has marker colorization ([*], [+], [-], [!])

  ## Examples

      iex> MsfailabWeb.Console.render_console_output("msf6 > ", "help", "[+] Success")
      {:safe, "<div>...</div><div class=\\"...\\">[+] Success</div>"}

  """
  # sobelow_skip ["XSS.Raw"]
  @spec render_console_output(String.t(), String.t(), String.t()) :: Phoenix.HTML.safe()
  def render_console_output(prompt, command, output)
      when is_binary(prompt) and is_binary(command) and is_binary(output) do
    command_html = console_command_html(prompt, command)
    output_html = colorized_output_html(output)
    Phoenix.HTML.raw("<div>#{command_html}</div>#{output_html}")
  end

  @doc """
  Renders bash command with output: # prompt + command + plain output.

  - Prompt is bold "#"
  - Command is bold
  - Output is plain (no colorization)

  ## Examples

      iex> MsfailabWeb.Console.render_bash_output("ls -la", "file1\\nfile2")
      {:safe, "<div><strong># ls -la</strong></div><div>...</div>"}

  """
  # sobelow_skip ["XSS.Raw"]
  @spec render_bash_output(String.t(), String.t()) :: Phoenix.HTML.safe()
  def render_bash_output(command, output) when is_binary(command) and is_binary(output) do
    command_html = bash_command_html(command)
    output_html = plain_output_html(output)
    Phoenix.HTML.raw("<div>#{command_html}</div>#{output_html}")
  end

  # Internal HTML builders (return raw strings, not safe tuples)
  defp console_command_html(prompt, command) do
    "#{format_prompt_parts(prompt)}<strong>#{escape(command)}</strong>"
  end

  defp bash_command_html(command) do
    "<strong># #{escape(command)}</strong>"
  end

  defp colorized_output_html(""), do: ""

  defp colorized_output_html(output) do
    output
    |> String.split("\n")
    |> Enum.map_join("\n", &colorize_line/1)
    |> then(&"<div class=\"mt-1 whitespace-pre-wrap\">#{&1}</div>")
  end

  defp plain_output_html(""), do: ""

  defp plain_output_html(output) do
    "<div class=\"mt-1 whitespace-pre-wrap\">#{escape(output)}</div>"
  end

  # Format prompt parts with MSF-specific styling
  # Pattern: "msf6 exploit(unix/http/foo) > " or "msf6 > "
  defp format_prompt_parts(prompt) do
    # Parse the prompt into parts and style them using PromptFormatter
    escape_fn = fn text ->
      {:safe, escaped} = Phoenix.HTML.html_escape(text)
      {:safe, escaped}
    end

    prompt
    |> PromptFormatter.parse_prompt_tokens()
    |> Enum.map_join(&PromptFormatter.render_token(&1, escape_fn))
    |> wrap_bold()
  end

  defp wrap_bold(html), do: "<strong>#{html}</strong>"

  # Metasploit symbol colorization - only the marker is colored
  defp colorize_line("[*]" <> rest), do: ~s(<span class="text-info">[*]</span>#{escape(rest)})
  defp colorize_line("[+]" <> rest), do: ~s(<span class="text-success">[+]</span>#{escape(rest)})
  defp colorize_line("[-]" <> rest), do: ~s(<span class="text-error">[-]</span>#{escape(rest)})
  defp colorize_line("[!]" <> rest), do: ~s(<span class="text-warning">[!]</span>#{escape(rest)})
  defp colorize_line(line), do: escape(line)

  defp escape(text) do
    {:safe, escaped} = Phoenix.HTML.html_escape(text)
    IO.iodata_to_binary(escaped)
  end
end
