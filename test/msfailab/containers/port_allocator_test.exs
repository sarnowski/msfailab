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

defmodule Msfailab.Containers.PortAllocatorTest do
  use ExUnit.Case, async: true

  alias Msfailab.Containers.PortAllocator

  describe "allocate_port/1" do
    test "returns port in 50000-60000 range when used_ports is empty" do
      {:ok, port} = PortAllocator.allocate_port([])

      assert port >= 50_000
      assert port <= 60_000
    end

    test "returns port not in used_ports list" do
      used_ports = [50_001, 50_002, 50_003]

      {:ok, port} = PortAllocator.allocate_port(used_ports)

      assert port >= 50_000
      assert port <= 60_000
      refute port in used_ports
    end

    test "eventually finds a free port when most are used" do
      # Use all but one port
      all_ports = Enum.to_list(50_000..60_000)
      free_port = 55_555
      used_ports = List.delete(all_ports, free_port)

      {:ok, port} = PortAllocator.allocate_port(used_ports)

      assert port == free_port
    end

    test "returns error when all ports in range are used" do
      all_ports = Enum.to_list(50_000..60_000)

      assert {:error, :no_ports_available} = PortAllocator.allocate_port(all_ports)
    end
  end

  describe "port_range/0" do
    test "returns the configured port range" do
      assert PortAllocator.port_range() == 50_000..60_000
    end
  end
end
