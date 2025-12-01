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

    test "colorizes [*] status lines as info (cyan)" do
      {:safe, html} = Console.to_html("[*] Starting scan")
      assert html =~ ~s(<span class="text-info">[*] Starting scan</span>)
    end

    test "colorizes [+] success lines as success (green)" do
      {:safe, html} = Console.to_html("[+] Exploit succeeded")
      assert html =~ ~s(<span class="text-success">[+] Exploit succeeded</span>)
    end

    test "colorizes [-] error lines as error (red)" do
      {:safe, html} = Console.to_html("[-] Connection failed")
      assert html =~ ~s(<span class="text-error">[-] Connection failed</span>)
    end

    test "colorizes [!] warning lines as warning (yellow)" do
      {:safe, html} = Console.to_html("[!] Deprecated option")
      assert html =~ ~s(<span class="text-warning">[!] Deprecated option</span>)
    end

    test "handles multiline output with mixed symbols" do
      input = "[*] Starting module\n[+] Success\n[-] Error occurred\n[!] Warning\nPlain text"

      {:safe, html} = Console.to_html(input)

      assert html =~ ~s(<span class="text-info">[*] Starting module</span>)
      assert html =~ ~s(<span class="text-success">[+] Success</span>)
      assert html =~ ~s(<span class="text-error">[-] Error occurred</span>)
      assert html =~ ~s(<span class="text-warning">[!] Warning</span>)
      assert html =~ "Plain text"
    end

    test "escapes HTML within colorized lines" do
      {:safe, html} = Console.to_html("[+] Got <shell> access")
      assert html =~ "&lt;shell&gt;"
      assert html =~ ~s(<span class="text-success">)
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
