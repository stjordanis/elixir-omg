use Mix.Config

config :porcelain, :goon_warn_if_missing, false

config :ethereumex,
  scheme: "http",
  host: "localhost",
  port: 8545,
  url: "http://localhost:8545",
  request_timeout: 5000

import_config "#{Mix.env()}.exs"
