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
  @moduledoc """
  Renders Metasploit console output with syntax highlighting.

  Colorizes lines based on standard Metasploit prefix symbols:
  - `[*]` → Cyan (status/info)
  - `[+]` → Green (success)
  - `[-]` → Red (error)
  - `[!]` → Yellow (warning)
  """

  @doc """
  Converts console text to HTML with Metasploit symbol colorization.

  Returns a Phoenix.HTML.safe() tuple that can be directly rendered in templates.
  Text content is properly HTML-escaped.

  ## Examples

      iex> MsfailabWeb.Console.to_html("[+] Success!")
      {:safe, "<span class=\\"text-success\\">[+] Success!</span>"}

      iex> MsfailabWeb.Console.to_html("[-] Failed")
      {:safe, "<span class=\\"text-error\\">[-] Failed</span>"}

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

  # Metasploit symbol to Tailwind/DaisyUI class mapping
  defp colorize_line("[*]" <> rest), do: ~s(<span class="text-info">[*]#{escape(rest)}</span>)
  defp colorize_line("[+]" <> rest), do: ~s(<span class="text-success">[+]#{escape(rest)}</span>)
  defp colorize_line("[-]" <> rest), do: ~s(<span class="text-error">[-]#{escape(rest)}</span>)
  defp colorize_line("[!]" <> rest), do: ~s(<span class="text-warning">[!]#{escape(rest)}</span>)
  defp colorize_line(line), do: escape(line)

  defp escape(text) do
    {:safe, escaped} = Phoenix.HTML.html_escape(text)
    IO.iodata_to_binary(escaped)
  end
end
