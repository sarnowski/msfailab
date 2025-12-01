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

defmodule MsfailabWeb.ConsoleTest do
  use ExUnit.Case, async: true

  alias MsfailabWeb.Console

  describe "to_html/1" do
    test "returns plain text unchanged" do
      assert {:safe, "hello world"} = Console.to_html("hello world")
    end

    test "escapes HTML in plain text" do
      assert {:safe, "&lt;script&gt;alert(1)&lt;/script&gt;"} =
               Console.to_html("<script>alert(1)</script>")
    end

    test "colorizes only [*] marker as info, not entire line" do
      {:safe, html} = Console.to_html("[*] Starting scan")
      # Only the marker is colored, rest of line is plain escaped text
      assert html == ~s(<span class="text-info">[*]</span> Starting scan)
    end

    test "colorizes only [+] marker as success, not entire line" do
      {:safe, html} = Console.to_html("[+] Exploit succeeded")
      assert html == ~s(<span class="text-success">[+]</span> Exploit succeeded)
    end

    test "colorizes only [-] marker as error, not entire line" do
      {:safe, html} = Console.to_html("[-] Connection failed")
      assert html == ~s(<span class="text-error">[-]</span> Connection failed)
    end

    test "colorizes only [!] marker as warning, not entire line" do
      {:safe, html} = Console.to_html("[!] Deprecated option")
      assert html == ~s(<span class="text-warning">[!]</span> Deprecated option)
    end

    test "handles multiline output with mixed symbols" do
      input = "[*] Starting module\n[+] Success\n[-] Error occurred\n[!] Warning\nPlain text"

      {:safe, html} = Console.to_html(input)

      # Each line should have only its marker colored
      assert html =~ ~s(<span class="text-info">[*]</span> Starting module)
      assert html =~ ~s(<span class="text-success">[+]</span> Success)
      assert html =~ ~s(<span class="text-error">[-]</span> Error occurred)
      assert html =~ ~s(<span class="text-warning">[!]</span> Warning)
      assert html =~ "Plain text"
    end

    test "escapes HTML within colorized lines" do
      {:safe, html} = Console.to_html("[+] Got <shell> access")
      assert html =~ "&lt;shell&gt;"
      assert html =~ ~s(<span class="text-success">[+]</span>)
    end

    test "handles empty string" do
      assert {:safe, ""} = Console.to_html("")
    end

    test "preserves whitespace" do
      {:safe, html} = Console.to_html("  indented\n\ttabbed")
      assert html =~ "  indented"
      assert html =~ "\ttabbed"
    end
  end
end
