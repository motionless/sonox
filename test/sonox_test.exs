defmodule SonoxTest do
  use ExUnit.Case
  doctest Sonox

  test "greets the world" do
    assert Sonox.hello() == :world
  end
end
