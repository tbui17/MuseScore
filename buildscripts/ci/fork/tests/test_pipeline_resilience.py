"""Bounded transient recovery must never replay release writes or hide real errors."""
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import call, patch
from urllib.error import HTTPError, URLError

SPEC = importlib.util.spec_from_file_location("pipeline_resilience", Path(__file__).resolve().parents[1] / "pipeline.py")
pipeline = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pipeline)


def http_error(code, headers=None):
    return HTTPError("https://api.github.com/test", code, "test failure", headers or {}, io.BytesIO())


def success():
    return io.BytesIO(b'{"sha": "verified"}')


class ApiResilienceTests(unittest.TestCase):
    def setUp(self):
        opener = patch.object(pipeline.urllib.request, "urlopen")
        self.open = opener.start()
        self.addCleanup(opener.stop)
        sleeper = patch.object(pipeline.time, "sleep")
        self.sleep = sleeper.start()
        self.addCleanup(sleeper.stop)

    def test_success_needs_no_retry_and_retains_timeout_and_auth(self):
        self.open.return_value = success()
        with patch.dict(os.environ, {"GH_TOKEN": "test-token"}):
            self.assertEqual(pipeline.api("test"), {"sha": "verified"})
        self.assertEqual(self.open.call_count, 1)
        request = self.open.call_args.args[0]
        self.assertEqual(request.get_header("Authorization"), "Bearer test-token")
        self.assertEqual(self.open.call_args.kwargs["timeout"], 60)
        self.sleep.assert_not_called()

    def test_transient_http_errors_recover_and_close_error_streams(self):
        for code in (500, 502, 503, 504):
            with self.subTest(code=code):
                self.open.reset_mock()
                self.sleep.reset_mock()
                error = http_error(code)
                self.open.side_effect = [error, success()]
                self.assertEqual(pipeline.api("test"), {"sha": "verified"})
                self.assertEqual(self.open.call_count, 2)
                self.assertTrue(error.fp.closed)
                self.sleep.assert_called_once_with(1)

    def test_transient_transport_errors_recover(self):
        for error in (URLError("connection reset"), TimeoutError(), ConnectionResetError(),
                      pipeline.http.client.IncompleteRead(b"partial")):
            with self.subTest(error=type(error).__name__):
                self.open.reset_mock()
                self.sleep.reset_mock()
                self.open.side_effect = [error, success()]
                self.assertEqual(pipeline.api("test"), {"sha": "verified"})
                self.sleep.assert_called_once_with(1)

    def test_http_retry_budget_is_finite(self):
        self.open.side_effect = [http_error(503) for _ in range(4)]
        with self.assertRaisesRegex(RuntimeError, "HTTP 503"):
            pipeline.api("test")
        self.assertEqual(self.open.call_count, 4)
        self.assertEqual(self.sleep.call_args_list, [call(1), call(2), call(4)])

    def test_transport_retry_budget_is_finite(self):
        self.open.side_effect = URLError("offline")
        with self.assertRaisesRegex(RuntimeError, "transport failure"):
            pipeline.api("test")
        self.assertEqual(self.open.call_count, 4)
        self.assertEqual(self.sleep.call_args_list, [call(1), call(2), call(4)])

    def test_mutations_are_never_retried(self):
        for method in ("POST", "PATCH", "PUT", "DELETE"):
            for error in (http_error(503), URLError("ambiguous outcome"), TimeoutError()):
                with self.subTest(method=method, error=type(error).__name__):
                    self.open.reset_mock()
                    self.sleep.reset_mock()
                    self.open.side_effect = error
                    with self.assertRaises(RuntimeError):
                        pipeline.api("test", method=method, data={"draft": True})
                    self.assertEqual(self.open.call_count, 1)
                    self.sleep.assert_not_called()

    def test_client_and_rate_limit_errors_fail_without_retry(self):
        for code in (400, 401, 403, 404, 409, 422, 429):
            with self.subTest(code=code):
                self.open.reset_mock()
                self.open.side_effect = http_error(code)
                with self.assertRaisesRegex(RuntimeError, f"HTTP {code}"):
                    pipeline.api("test")
                self.assertEqual(self.open.call_count, 1)
                self.sleep.assert_not_called()

    def test_optional_missing_read_is_not_an_error_or_retry(self):
        error = http_error(404)
        self.open.side_effect = error
        self.assertIsNone(pipeline.api("test", missing_ok=True))
        self.assertTrue(error.fp.closed)
        self.sleep.assert_not_called()

    def test_missing_ok_does_not_hide_a_failed_write(self):
        self.open.side_effect = http_error(404)
        with self.assertRaisesRegex(RuntimeError, "HTTP 404"):
            pipeline.api("test", method="POST", missing_ok=True)
        self.sleep.assert_not_called()

    def test_retry_after_seconds_is_honored(self):
        self.open.side_effect = [http_error(503, {"Retry-After": "12"}), success()]
        pipeline.api("test")
        self.sleep.assert_called_once_with(12)

    def test_retry_after_http_date_is_honored(self):
        self.open.side_effect = [http_error(503, {"Retry-After": "Thu, 01 Jan 1970 00:00:12 GMT"}), success()]
        with patch.object(pipeline.time, "time", return_value=0):
            pipeline.api("test")
        self.sleep.assert_called_once_with(12)

    def test_invalid_or_excessive_retry_after_fails_instead_of_retrying_early(self):
        for value in ("120", "not-a-date", "-3"):
            with self.subTest(value=value):
                self.open.reset_mock()
                error = http_error(503, {"Retry-After": value})
                self.open.side_effect = error
                with self.assertRaisesRegex(RuntimeError, "Retry-After"):
                    pipeline.api("test")
                self.assertEqual(self.open.call_count, 1)
                self.assertTrue(error.fp.closed)
                self.sleep.assert_not_called()

    def test_malformed_json_is_not_treated_as_a_transport_retry(self):
        response = io.BytesIO(b"not JSON")
        self.open.return_value = response
        with self.assertRaises(json.JSONDecodeError):
            pipeline.api("test")
        self.assertTrue(response.closed)
        self.assertEqual(self.open.call_count, 1)
        self.sleep.assert_not_called()


class CommandResilienceTests(unittest.TestCase):
    def test_commands_are_bounded_and_noninteractive(self):
        with patch.object(pipeline.subprocess, "run") as run:
            run.return_value.stdout = " result \n"
            with patch.dict(os.environ, {"GIT_TERMINAL_PROMPT": "1", "PRESERVED": "yes"}):
                self.assertEqual(pipeline.command("git", "status", cwd=Path(".")), "result")
            self.assertEqual(run.call_args.args[0], ("git", "status"))
            options = run.call_args.kwargs
            self.assertEqual(options["timeout"], 900)
            self.assertEqual(options["stdin"], subprocess.DEVNULL)
            self.assertEqual(options["env"]["GIT_TERMINAL_PROMPT"], "0")
            self.assertEqual(options["env"]["PRESERVED"], "yes")
            self.assertTrue(options["check"])

    def test_command_timeout_is_not_retried_or_swallowed(self):
        with patch.object(pipeline.subprocess, "run", side_effect=subprocess.TimeoutExpired("git", 900)) as run:
            with self.assertRaises(subprocess.TimeoutExpired):
                pipeline.command("git", "fetch")
            self.assertEqual(run.call_count, 1)

    def test_real_command_keeps_stdout_contract(self):
        self.assertEqual(pipeline.command(sys.executable, "-c", "print('ok')"), "ok")


if __name__ == "__main__":
    unittest.main()
