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

defmodule MsfailabWeb.Router do
  @moduledoc """
  Phoenix router defining application routes and pipelines.
  """
  use MsfailabWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MsfailabWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' wss:"
    }
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MsfailabWeb do
    pipe_through :browser

    # Landing page - workspace overview
    live "/", WorkspaceOverviewLive, :index

    # Workspace routes
    # /<workspace-slug> - Asset Library view
    live "/:workspace_slug", WorkspaceLive, :asset_library
    # /<workspace-slug>/<track-slug> - Track view
    live "/:workspace_slug/:track_slug", WorkspaceLive, :track
  end

  # Other scopes may use custom stacks.
  # scope "/api", MsfailabWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  # coveralls-ignore-start
  # Reason: Development-only routes not used in test environment
  if Application.compile_env(:msfailab, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MsfailabWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # coveralls-ignore-stop
end
