[
  ## don't run tools concurrently
  parallel: false,

  ## don't print info about skipped tools
  # skipped: false,

  ## always run tools in fix mode (put it in ~/.check.exs locally, not in project config)
  # fix: true,

  ## don't retry automatically even if last run resulted in failures
  retry: false,

  ## list of tools (see `mix check` docs for a list of default curated tools)
  tools: [
    # no need to generate doc
    {:ex_doc, false},

    ## enforce recompilation with all warnings as errors
    {:compiler, "mix compile --force --warnings-as-errors"},

    ## some framework warnings must be ignored
    {:dialyzer, "mix dialyzer --format ignore_file_strict"},

    ## report all issues
    {:credo, "mix credo --strict"},

    ## enforce strict security checks except for Config.HTTPS which needs to be done by the http proxy
    {:sobelow, "mix sobelow --exit --skip --verbose --threshold low --ignore Config.HTTPS"},

    ## ...or reconfigured (e.g. disable parallel execution of ex_unit in umbrella)
    # {:ex_unit, umbrella: [parallel: false]},
    {:ex_unit, "mix test --force --all-warnings --warnings-as-errors"},

    ## create a coverage report with excoveralls
    {:coveralls, "mix coveralls"},

    ## run JavaScript unit tests via npm (Tier 2 testing)
    {:npm_test, "npm test", cd: "assets"}

    ## custom new tools may be added (Mix tasks or arbitrary commands)
    # {:my_task, "mix my_task", env: %{"MIX_ENV" => "prod"}},
    # {:my_tool, ["my_tool", "arg with spaces"]}
  ]
]
