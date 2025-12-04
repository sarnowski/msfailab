[
  # Mix tasks use Mix.Task which is not in PLT (build-time only)
  {"lib/mix/tasks/msfailab.seed.ex",
   "Callback info about the Mix.Task behaviour is not available."},
  {"lib/mix/tasks/msfailab.seed.ex", "Function Mix.Task.run/1 does not exist."},

  # False positive: Dialyzer thinks Process.whereis always returns nil during analysis
  # because the Registry isn't running at compile time. At runtime, get_track_state
  # can return {:ok, state} when TrackServer is running.
  {"lib/msfailab_web/live/workspace_live.ex", :pattern_match}
]
