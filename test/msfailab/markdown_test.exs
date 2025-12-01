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

defmodule Msfailab.MarkdownTest do
  use ExUnit.Case, async: true

  alias Msfailab.Markdown

  describe "render/1" do
    test "renders simple markdown to HTML" do
      assert {:ok, html} = Markdown.render("# Hello")
      assert html =~ "<h1>"
      assert html =~ "Hello"
    end

    test "renders paragraphs" do
      assert {:ok, html} = Markdown.render("Hello world")
      assert html =~ "<p>"
    end

    test "renders code blocks with syntax highlighting" do
      assert {:ok, html} = Markdown.render("```elixir\ndef foo, do: :bar\n```")
      assert html =~ "<pre"
      assert html =~ "<code"
    end
  end

  describe "render!/1" do
    test "renders markdown and raises on error" do
      html = Markdown.render!("**bold**")
      assert html =~ "<strong>"
      assert html =~ "bold"
    end
  end

  describe "streaming document" do
    test "creates and renders streaming content" do
      doc = Markdown.new_streaming_document()
      {html, _doc} = Markdown.put_and_render(doc, "# Title")
      assert html =~ "<h1>"
      assert html =~ "Title"
    end

    test "accumulates content across multiple puts" do
      doc = Markdown.new_streaming_document()
      {html1, doc} = Markdown.put_and_render(doc, "Hello ")
      {html2, _doc} = Markdown.put_and_render(doc, "World")

      assert html1 =~ "Hello"
      assert html2 =~ "Hello"
      assert html2 =~ "World"
    end
  end
end
