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

  describe "format_prompt/1" do
    test "formats simple prompt without module" do
      {:safe, html} = Console.format_prompt("msf6 > ")
      assert html =~ "<u>msf</u>"
      assert html =~ "<strong>"
      assert html =~ "&gt;"
    end

    test "formats prompt with exploit module" do
      {:safe, html} = Console.format_prompt("msf6 exploit(unix/http/foo) > ")
      assert html =~ "<u>msf</u>"
      assert html =~ "exploit"
      assert html =~ ~s(<span class="text-error">unix/http/foo</span>)
      assert html =~ "<strong>"
    end

    test "formats prompt with auxiliary module" do
      {:safe, html} = Console.format_prompt("msf6 auxiliary(scanner/ssh/ssh_login) > ")
      assert html =~ "<u>msf</u>"
      assert html =~ "auxiliary"
      assert html =~ ~s(<span class="text-error">scanner/ssh/ssh_login</span>)
    end

    test "escapes special characters in prompt" do
      {:safe, html} = Console.format_prompt("msf6 <test> > ")
      assert html =~ "&lt;test&gt;"
    end
  end

  describe "render_console_command/2" do
    test "renders prompt with command" do
      {:safe, html} = Console.render_console_command("msf6 > ", "help")
      assert html =~ "<u>msf</u>"
      assert html =~ "<strong>help</strong>"
    end

    test "escapes HTML in command" do
      {:safe, html} = Console.render_console_command("msf6 > ", "<script>alert(1)</script>")
      assert html =~ "&lt;script&gt;"
      refute html =~ "<script>"
    end

    test "renders prompt with module and command" do
      {:safe, html} =
        Console.render_console_command("msf6 exploit(unix/http/foo) > ", "set RHOST 127.0.0.1")

      assert html =~ ~s(<span class="text-error">unix/http/foo</span>)
      assert html =~ "<strong>set RHOST 127.0.0.1</strong>"
    end
  end

  describe "render_bash_command/1" do
    test "renders bash command with # prefix" do
      {:safe, html} = Console.render_bash_command("ls -la")
      assert html == "<strong># ls -la</strong>"
    end

    test "escapes HTML in bash command" do
      {:safe, html} = Console.render_bash_command("echo '<script>'")
      assert html =~ "&lt;script&gt;"
      assert html =~ "<strong># "
    end

    test "handles empty command" do
      {:safe, html} = Console.render_bash_command("")
      assert html == "<strong># </strong>"
    end
  end

  describe "render_console_output/3" do
    test "renders prompt, command, and output" do
      {:safe, html} = Console.render_console_output("msf6 > ", "help", "[+] Success")
      assert html =~ ~s(<div class="whitespace-pre-wrap">)
      assert html =~ "<u>msf</u>"
      assert html =~ "<strong>help</strong>"
      assert html =~ ~s(<span class="text-success">[+]</span>)
      assert html =~ "Success"
    end

    test "colorizes output markers" do
      {:safe, html} =
        Console.render_console_output("msf6 > ", "run", "[*] Starting\n[+] Done\n[-] Error")

      assert html =~ ~s(<span class="text-info">[*]</span>)
      assert html =~ ~s(<span class="text-success">[+]</span>)
      assert html =~ ~s(<span class="text-error">[-]</span>)
    end

    test "handles empty output" do
      {:safe, html} = Console.render_console_output("msf6 > ", "help", "")
      assert html =~ "<strong>help</strong>"
      refute html =~ "mt-1"
    end

    test "escapes HTML in output" do
      {:safe, html} = Console.render_console_output("msf6 > ", "cmd", "<script>evil</script>")
      assert html =~ "&lt;script&gt;"
    end
  end

  describe "render_bash_output/2" do
    test "renders bash command with output" do
      {:safe, html} = Console.render_bash_output("ls -la", "file1\nfile2")
      assert html =~ "<strong># ls -la</strong>"
      assert html =~ "file1"
      assert html =~ "file2"
    end

    test "handles empty output" do
      {:safe, html} = Console.render_bash_output("pwd", "")
      assert html =~ "<strong># pwd</strong>"
      refute html =~ "mt-1"
    end

    test "escapes HTML in output" do
      {:safe, html} = Console.render_bash_output("echo test", "<script>alert(1)</script>")
      assert html =~ "&lt;script&gt;"
      refute html =~ "<script>alert"
    end

    test "does not colorize markers in bash output (plain output)" do
      {:safe, html} = Console.render_bash_output("cat file", "[+] This is text")
      # Bash output is plain, so markers are not colorized
      refute html =~ "text-success"
      assert html =~ "[+] This is text"
    end
  end
end
