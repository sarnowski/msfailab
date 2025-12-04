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

defmodule MsfailabWeb.Console.PromptFormatterTest do
  use ExUnit.Case, async: true

  alias MsfailabWeb.Console.PromptFormatter

  describe "parse_prompt_tokens/1" do
    test "parses simple prompt without module" do
      tokens = PromptFormatter.parse_prompt_tokens("msf6 > ")
      assert [{:msf, "msf"}, {:text, "6 > "}] = tokens
    end

    test "parses prompt with exploit module" do
      tokens = PromptFormatter.parse_prompt_tokens("msf6 exploit(unix/http/foo) > ")

      assert [
               {:msf, "msf"},
               {:text, "6 exploit"},
               {:text, "("},
               {:paren_content, "unix/http/foo"},
               {:text, ")"},
               {:text, " > "}
             ] = tokens
    end

    test "parses prompt with auxiliary module" do
      tokens = PromptFormatter.parse_prompt_tokens("msf6 auxiliary(scanner/ssh/ssh_login) > ")

      assert [
               {:msf, "msf"},
               {:text, "6 auxiliary"},
               {:text, "("},
               {:paren_content, "scanner/ssh/ssh_login"},
               {:text, ")"},
               {:text, " > "}
             ] = tokens
    end

    test "parses prompt without msf prefix" do
      tokens = PromptFormatter.parse_prompt_tokens("custom_prompt > ")
      assert [{:text, "custom_prompt > "}] = tokens
    end

    test "handles empty prompt" do
      tokens = PromptFormatter.parse_prompt_tokens("")
      assert [] = tokens
    end
  end

  describe "classify_tokens/2" do
    test "classifies msf token" do
      tokens = PromptFormatter.classify_tokens(["msf", "6 > "], [])
      assert [{:msf, "msf"}, {:text, "6 > "}] = tokens
    end

    test "classifies parenthesized content" do
      tokens = PromptFormatter.classify_tokens(["(", "path", ")"], [])
      assert [{:text, "("}, {:paren_content, "path"}, {:text, ")"}] = tokens
    end

    test "handles unclosed parenthesis" do
      tokens = PromptFormatter.classify_tokens(["(", "path"], [])
      assert [{:text, "("}, {:paren_content, "path"}] = tokens
    end

    test "handles empty list" do
      tokens = PromptFormatter.classify_tokens([], [])
      assert [] = tokens
    end
  end

  describe "classify_paren_content/2" do
    test "marks content as paren_content" do
      tokens = PromptFormatter.classify_paren_content(["path", ")"], [])
      assert [{:text, "("}, {:paren_content, "path"}, {:text, ")"}] = tokens
    end

    test "handles immediate close paren" do
      tokens = PromptFormatter.classify_paren_content([")"], [])
      assert [{:text, ")"}] = tokens
    end

    test "handles empty content before close" do
      tokens = PromptFormatter.classify_paren_content([], [])
      assert [] = tokens
    end
  end

  describe "render_token/2" do
    # Simple escape function for testing
    defp escape(text), do: {:safe, text}

    test "renders msf token with underline" do
      html = PromptFormatter.render_token({:msf, "msf"}, &escape/1)
      assert html == "<u>msf</u>"
    end

    test "renders paren_content with error color" do
      html = PromptFormatter.render_token({:paren_content, "path"}, &escape/1)
      assert html == ~s(<span class="text-error">path</span>)
    end

    test "renders text token plain" do
      html = PromptFormatter.render_token({:text, "hello"}, &escape/1)
      assert html == "hello"
    end

    test "escapes special characters" do
      escape_fn = fn text ->
        {:safe, String.replace(text, ">", "&gt;")}
      end

      html = PromptFormatter.render_token({:text, ">"}, escape_fn)
      assert html == "&gt;"
    end
  end
end
