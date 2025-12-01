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

defmodule Msfailab.LLM.Model do
  @moduledoc """
  Represents an LLM model available through a provider.

  All models are cached at application startup and remain static
  until the application restarts.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          provider: :ollama | :openai | :anthropic,
          context_window: pos_integer()
        }

  @enforce_keys [:name, :provider, :context_window]
  defstruct [:name, :provider, :context_window]
end
