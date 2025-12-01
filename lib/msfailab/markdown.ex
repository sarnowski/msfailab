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

defmodule Msfailab.Markdown do
  @moduledoc """
  Markdown rendering with MDEx for chat messages.

  This module provides streaming-aware markdown rendering for the AI chat interface.
  It uses MDEx with the catppuccin_frappe theme for syntax highlighting and enables
  HTML sanitization for security.

  ## Streaming Support

  For streaming responses from LLMs, use `new_streaming_document/0` to create a
  document that buffers content, then `put_and_render/2` to add content and render.
  This handles partial markdown gracefully (e.g., unclosed `**bold` during stream).

  ## Security

  All output is sanitized to prevent XSS attacks. Raw HTML in markdown input is
  escaped, and the output goes through MDEx's ammonia-based sanitization.

  ## Example

      # For streaming content
      doc = Markdown.new_streaming_document()
      {html, doc} = Markdown.put_and_render(doc, "# Hello")
      {html, doc} = Markdown.put_and_render(doc, " World\\n\\nParagraph")

      # For complete content (persisted entries)
      {:ok, html} = Markdown.render("# Hello World")
  """

  @typedoc "MDEx document for streaming markdown"
  @type document :: MDEx.Document.t()

  @doc """
  Common options for markdown rendering.

  These options are shared between streaming and non-streaming rendering:
  - Extensions: tables, strikethrough, autolinks, tagfilter
  - Render: unsafe HTML is disabled (escaped)
  - Syntax highlighting: catppuccin_frappe theme
  - Sanitization: enabled for security
  """
  @spec options() :: keyword()
  def options do
    [
      extension: [
        table: true,
        strikethrough: true,
        autolink: true,
        tagfilter: true
      ],
      render: [
        unsafe_: false
      ],
      syntax_highlight: [
        formatter: {:html_inline, [theme: "gruvbox_light"]}
      ],
      sanitize: [
        generic_attribute_prefixes: ["style", "class", "data-"]
      ]
    ]
  end

  @doc """
  Creates a new streaming document for incremental markdown rendering.

  Use this when processing streaming LLM responses. The document buffers
  content and handles partial markdown (like unclosed bold markers) gracefully.

  ## Example

      doc = Markdown.new_streaming_document()
      {html, doc} = Markdown.put_and_render(doc, "**partial")
      # html contains valid output even with incomplete markdown
  """
  @spec new_streaming_document() :: document()
  def new_streaming_document do
    MDEx.new([{:streaming, true} | options()])
  end

  @doc """
  Adds content to a streaming document and renders to HTML.

  This function:
  1. Buffers the new content
  2. Parses the accumulated markdown
  3. Renders to sanitized HTML

  Returns `{html, updated_document}` tuple. The document maintains state
  for subsequent calls to handle multi-part content correctly.

  ## Example

      doc = Markdown.new_streaming_document()
      {html1, doc} = Markdown.put_and_render(doc, "# Title\\n")
      {html2, doc} = Markdown.put_and_render(doc, "More content")
  """
  @spec put_and_render(document(), String.t()) :: {String.t(), document()}
  def put_and_render(document, content) do
    document = MDEx.Document.put_markdown(document, content)

    case MDEx.to_html(document) do
      {:ok, html} -> {html, document}
      {:error, _reason} -> {"", document}
    end
  end

  @doc """
  Renders a complete markdown string to HTML.

  Use this for non-streaming content (e.g., persisted chat entries loaded from DB).

  ## Example

      {:ok, html} = Markdown.render("# Hello\\n\\nWorld")
  """
  @spec render(String.t()) :: {:ok, String.t()} | {:error, term()}
  def render(content) do
    MDEx.to_html(content, options())
  end

  @doc """
  Renders a complete markdown string to HTML, raising on error.

  ## Example

      html = Markdown.render!("# Hello")
  """
  @spec render!(String.t()) :: String.t()
  def render!(content) do
    MDEx.to_html!(content, options())
  end
end
