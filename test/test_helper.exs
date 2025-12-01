ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Msfailab.Repo, :manual)

# Define Mox mocks
Mox.defmock(Msfailab.Containers.DockerAdapterMock,
  for: Msfailab.Containers.DockerAdapter
)

Mox.defmock(Msfailab.Containers.Msgrpc.ClientMock,
  for: Msfailab.Containers.Msgrpc.Client
)

Mox.defmock(Msfailab.LLM.ProviderMock,
  for: Msfailab.LLM.Provider
)
