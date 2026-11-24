defmodule BeginStatementTest do
  # Not async: two of these tests disconnect on purpose, which must not race the timing-sensitive
  # connection tests that run concurrently.
  use ExUnit.Case, async: false
  import Postgrex.TestHelper
  import ExUnit.CaptureLog
  alias Postgrex, as: P

  setup do
    opts = [
      database: "postgrex_test",
      transactions: :strict,
      idle: :active,
      backoff_type: :stop,
      max_restarts: 0
    ]

    {:ok, pid} = P.start_link(opts)
    {:ok, [pid: pid]}
  end

  test "begin_statement runs its statements in the transaction it opens", context do
    assert transaction(
             fn conn ->
               assert %Postgrex.Result{rows: [["y"]]} =
                        P.query!(conn, "SELECT current_setting('app.x')", [])
             end,
             begin_statement: "BEGIN;SET LOCAL app.x = 'y'",
             log: &send(self(), &1)
           )

    assert_receive %DBConnection.LogEntry{} = entry
    assert {:ok, %DBConnection{}, %Postgrex.Result{command: :begin}} = entry.result
    assert [[""]] = query("SELECT current_setting('app.x', true)", [])
  end

  test "begin_statement failing after BEGIN disconnects instead of leaving a transaction open",
       context do
    Process.flag(:trap_exit, true)

    capture_log(fn ->
      assert_raise Postgrex.Error, ~r/statement_timeout/, fn ->
        transaction(fn _conn -> :ok end,
          begin_statement: "BEGIN;SET LOCAL statement_timeout = 'bogus'"
        )
      end
    end)
  end

  test "begin_statement that does not open a transaction disconnects", context do
    Process.flag(:trap_exit, true)

    capture_log(fn ->
      assert_raise RuntimeError, ~r/did not open a transaction/, fn ->
        transaction(fn _conn -> :ok end, begin_statement: "BEGIN;COMMIT")
      end
    end)
  end
end
