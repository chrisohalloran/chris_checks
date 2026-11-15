defmodule ChrisChecks.Check.LiveViewTimerRequiresConnectedTest do
  use Credo.Test.Case, async: true

  alias ChrisChecks.Check.LiveViewTimerRequiresConnected, as: Check

  defp live(mount_body) do
    """
    defmodule MyAppWeb.ClockLive do
      use MyAppWeb, :live_view

      def mount(_params, _session, socket) do
    #{mount_body}
        {:ok, socket}
      end
    end
    """
  end

  test "flags an unguarded timer in mount/3" do
    "Process.send_after(self(), :tick, 1_000)"
    |> live()
    |> to_source_file()
    |> run_check(Check)
    |> assert_issue(fn issue ->
      assert issue.line_no == 5
      assert issue.trigger == "Process.send_after"

      assert issue.message ==
               "Process.send_after in `mount/3`: start timers only `if connected?(socket)`."
    end)
  end

  test "flags every :timer function" do
    """
    :timer.send_after(1_000, :tick)
    :timer.send_interval(1_000, :tick)
    :timer.apply_after(1_000, M, :f, [])
    :timer.apply_interval(1_000, M, :f, [])
    """
    |> live()
    |> to_source_file()
    |> run_check(Check)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.trigger) == [
               ":timer.send_after",
               ":timer.send_interval",
               ":timer.apply_after",
               ":timer.apply_interval"
             ]
    end)
  end

  test "accepts timers guarded by connected?" do
    """
    if connected?(socket), do: Process.send_after(self(), :tick, 1_000)
    if Phoenix.LiveView.connected?(socket) and ready, do: :timer.send_interval(1, :t)
    unless not connected?(socket), do: Process.send_after(self(), :a, 1)
    unless connected?(socket), do: :static, else: Process.send_after(self(), :b, 1)
    if !connected?(socket), do: :static, else: Process.send_after(self(), :c, 1)

    cond do
      connected?(socket) -> Process.send_after(self(), :d, 1)
      true -> :ok
    end
    """
    |> live()
    |> to_source_file()
    |> run_check(Check)
    |> refute_issues()
  end

  test "flags timers in the disconnected branch and in conditions" do
    """
    if connected?(socket), do: :ok, else: Process.send_after(self(), :a, 1)
    unless connected?(socket), do: Process.send_after(self(), :b, 1)
    if Process.send_after(self(), :c, 1), do: :ok

    cond do
      ready -> Process.send_after(self(), :d, 1)
      true -> :ok
    end
    """
    |> live()
    |> to_source_file()
    |> run_check(Check)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [5, 6, 7, 10] end)
  end

  test "resolves alias ... as:" do
    """
    defmodule MyAppWeb.ClockLive do
      alias :timer, as: T
      alias Process, as: P

      def mount(_params, _session, socket) when is_map(socket) do
        T.send_after(1_000, :tick)
        P.send_after(self(), :tick, 1_000)
        {:ok, socket}
      end
    end
    """
    |> to_source_file()
    |> run_check(Check)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.trigger) == ["T.send_after", "P.send_after"]
    end)
  end

  test "ignores other functions and other arities of mount" do
    """
    defmodule MyAppWeb.ClockLive do
      def handle_info(:tick, socket) do
        Process.send_after(self(), :tick, 1_000)
        {:noreply, socket}
      end

      def mount(socket), do: Process.send_after(self(), :tick, 1_000)
    end
    """
    |> to_source_file()
    |> run_check(Check)
    |> refute_issues()
  end
end
