defmodule XtouchMapper do
  @moduledoc """
  Documentation for `XtouchMapper`.
  """

  def start(_type, _args) do
    children = [
      Xtouch,
      {XAir, {192, 168, 241, 14}},
      Mapper
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
