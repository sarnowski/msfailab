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

defmodule Msfailab.Skills.Skill do
  @moduledoc """
  A skill that can be learned by the AI agent.

  Skills are markdown documents with YAML frontmatter containing
  `name` and `description` fields. The body contains the content
  that teaches the skill.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          filename: String.t(),
          body: String.t()
        }

  @enforce_keys [:name, :description, :filename, :body]
  defstruct [:name, :description, :filename, :body]
end
