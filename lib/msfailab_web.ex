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

defmodule MsfailabWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use MsfailabWeb, :controller
      use MsfailabWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  @doc """
  Returns the list of static paths for the application.
  """
  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)

  @doc """
  Returns quoted code for setting up a router module.
  """
  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  @doc """
  Returns quoted code for setting up a channel module.
  """
  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  @doc """
  Returns quoted code for setting up a controller module.
  """
  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]

      use Gettext, backend: MsfailabWeb.Gettext

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  @doc """
  Returns quoted code for setting up a LiveView module.
  """
  def live_view do
    quote do
      use Phoenix.LiveView

      unquote(html_helpers())
    end
  end

  @doc """
  Returns quoted code for setting up a LiveComponent module.
  """
  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  @doc """
  Returns quoted code for setting up an HTML rendering module.
  """
  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      # Translation
      use Gettext, backend: MsfailabWeb.Gettext

      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components
      import MsfailabWeb.CoreComponents
      # Workspace-specific UI components
      import MsfailabWeb.WorkspaceComponents

      # Common modules used in templates
      alias MsfailabWeb.Layouts
      alias Phoenix.LiveView.JS

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  @doc """
  Returns quoted code for setting up verified routes.
  """
  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: MsfailabWeb.Endpoint,
        router: MsfailabWeb.Router,
        statics: MsfailabWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
