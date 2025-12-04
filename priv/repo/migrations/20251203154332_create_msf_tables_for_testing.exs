defmodule Msfailab.Repo.Migrations.CreateMsfTablesForTesting do
  @moduledoc """
  Creates Metasploit Framework database tables for testing.

  These tables mirror the MSF database schema and are used for testing
  the MsfData context. In production, these tables are created and
  managed by Metasploit itself.

  Based on: https://github.com/rapid7/metasploit-framework/blob/master/db/schema.rb

  NOTE: This migration only runs in :test environment. In :dev and :prod,
  Metasploit creates and manages these tables with its own migrations.
  """
  use Ecto.Migration

  def change do
    # Only create MSF tables in test environment.
    # In dev/prod, Metasploit manages its own schema.
    if Mix.env() == :test do
      create_msf_tables()
    end
  end

  defp create_msf_tables do
    # MSF workspaces table
    create_if_not_exists table(:workspaces) do
      add :name, :string, size: 512
      add :boundary, :string, size: 4096
      add :description, :string, size: 4096

      timestamps(inserted_at: :created_at, type: :utc_datetime)
    end

    create_if_not_exists unique_index(:workspaces, [:name])

    # Hosts table
    create_if_not_exists table(:hosts) do
      add :address, :inet
      add :mac, :string
      add :name, :string, size: 512
      add :state, :string
      add :os_name, :string, size: 512
      add :os_flavor, :string, size: 512
      add :os_sp, :string, size: 512
      add :os_lang, :string, size: 512
      add :os_family, :string, size: 512
      add :arch, :string
      add :purpose, :string
      add :info, :string, size: 4096
      add :comments, :text
      add :workspace_id, references(:workspaces, on_delete: :delete_all)

      timestamps(inserted_at: :created_at, type: :utc_datetime)
    end

    create_if_not_exists index(:hosts, [:workspace_id])
    create_if_not_exists index(:hosts, [:address])

    # Services table
    create_if_not_exists table(:services) do
      add :host_id, references(:hosts, on_delete: :delete_all)
      add :port, :integer
      add :proto, :string, size: 16
      add :state, :string
      add :name, :string, size: 256
      add :info, :text

      timestamps(inserted_at: :created_at, type: :utc_datetime)
    end

    create_if_not_exists index(:services, [:host_id])
    create_if_not_exists index(:services, [:port])

    # Refs table (vulnerability references - CVE, MSB, EDB, etc.)
    create_if_not_exists table(:refs) do
      add :name, :string, size: 512

      timestamps(inserted_at: :created_at, type: :utc_datetime)
    end

    create_if_not_exists unique_index(:refs, [:name])

    # Vulns table
    create_if_not_exists table(:vulns) do
      add :host_id, references(:hosts, on_delete: :delete_all)
      add :service_id, references(:services, on_delete: :nilify_all)
      add :name, :string, size: 512
      add :info, :text
      add :exploited_at, :utc_datetime

      timestamps(inserted_at: :created_at, type: :utc_datetime)
    end

    create_if_not_exists index(:vulns, [:host_id])
    create_if_not_exists index(:vulns, [:service_id])

    # vulns_refs join table
    create_if_not_exists table(:vulns_refs, primary_key: false) do
      add :vuln_id, references(:vulns, on_delete: :delete_all), null: false
      add :ref_id, references(:refs, on_delete: :delete_all), null: false
    end

    create_if_not_exists unique_index(:vulns_refs, [:vuln_id, :ref_id])

    # Notes table
    create_if_not_exists table(:notes) do
      add :ntype, :string, size: 512
      add :data, :text
      add :critical, :boolean, default: false
      add :seen, :boolean, default: false
      add :workspace_id, references(:workspaces, on_delete: :delete_all)
      add :host_id, references(:hosts, on_delete: :delete_all)
      add :service_id, references(:services, on_delete: :delete_all)
      add :vuln_id, references(:vulns, on_delete: :delete_all)

      timestamps(inserted_at: :created_at, type: :utc_datetime)
    end

    create_if_not_exists index(:notes, [:workspace_id])
    create_if_not_exists index(:notes, [:ntype])

    # Creds table
    create_if_not_exists table(:creds) do
      add :service_id, references(:services, on_delete: :delete_all)
      add :user, :string, size: 512
      add :pass, :string, size: 4096
      add :ptype, :string, size: 256
      add :active, :boolean, default: true
      add :proof, :text
      add :source_id, :integer
      add :source_type, :string

      timestamps(inserted_at: :created_at, type: :utc_datetime)
    end

    create_if_not_exists index(:creds, [:service_id])

    # Loots table
    create_if_not_exists table(:loots) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all)
      add :host_id, references(:hosts, on_delete: :delete_all)
      add :service_id, references(:services, on_delete: :delete_all)
      add :ltype, :string, size: 512
      add :path, :string, size: 4096
      add :data, :text
      add :content_type, :string, size: 256
      add :name, :string, size: 512
      add :info, :text

      timestamps(inserted_at: :created_at, type: :utc_datetime)
    end

    create_if_not_exists index(:loots, [:workspace_id])

    # Sessions table (no timestamps - MSF only has opened_at/closed_at)
    create_if_not_exists table(:sessions) do
      add :host_id, references(:hosts, on_delete: :delete_all)
      add :stype, :string, size: 256
      add :via_exploit, :string
      add :via_payload, :string
      add :desc, :string
      add :port, :integer
      add :platform, :string
      add :opened_at, :utc_datetime
      add :closed_at, :utc_datetime
    end

    create_if_not_exists index(:sessions, [:host_id])
  end
end
