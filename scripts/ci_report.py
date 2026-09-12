#!/usr/bin/env python3
"""Produce a truthful report from one macOS verification run.

The script deliberately fails closed: a missing result bundle, empty test
summary, missing coverage target, warning, or failed command is not reported
as a pass. It is executed by remote-verify.sh on macOS; Windows only runs the
source and syntax gates and must not call this as an iOS verification.
"""
from __future__ import annotations

import argparse
import json
import platform
import re
import subprocess
from pathlib import Path
from typing import Any


def run_json(command: list[str]) -> dict[str, Any] | None:
    try:
        output = subprocess.check_output(command, stderr=subprocess.PIPE, text=True)
        value = json.loads(output)
        return value if isinstance(value, dict) else None
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError):
        return None


def first_number(value: Any, names: tuple[str, ...]) -> int | None:
    if isinstance(value, dict):
        for name in names:
            candidate = value.get(name)
            if isinstance(candidate, (int, float)):
                return int(candidate)
        for child in value.values():
            result = first_number(child, names)
            if result is not None:
                return result
    elif isinstance(value, list):
        for child in value:
            result = first_number(child, names)
            if result is not None:
                return result
    return None


def collect_named_coverage(value: Any, names: list[tuple[str, float]]) -> None:
    if isinstance(value, dict):
        name = value.get("name")
        coverage = value.get("lineCoverage")
        if isinstance(name, str) and isinstance(coverage, (int, float)):
            names.append((name, float(coverage)))
        for child in value.values():
            collect_named_coverage(child, names)
    elif isinstance(value, list):
        for child in value:
            collect_named_coverage(child, names)


def normalized(value: float) -> float:
    return value / 100.0 if value > 1.0 else value


def coverage_result(result_bundle: Path) -> tuple[str, bool]:
    payload = run_json(["xcrun", "xccov", "view", "--report", "--json", str(result_bundle)])
    if payload is None:
        return "xccov report unavailable", False
    entries: list[tuple[str, float]] = []
    collect_named_coverage(payload, entries)
    app_entries = [(name, normalized(value)) for name, value in entries if name in {"BPHealth", "BPHealth.app"} or name.endswith("/BPHealth.app")]
    rule_entries = [(name, normalized(value)) for name, value in entries if name == "Rules.swift" or name.endswith("/Rules.swift")]
    if not app_entries or not rule_entries:
        return "coverage target missing (BPHealth or Rules.swift)", False
    overall = max(value for _, value in app_entries)
    core = max(value for _, value in rule_entries)
    passed = overall >= 0.80 and core >= 0.90
    return f"overall={overall * 100:.2f}%; core-rules={core * 100:.2f}%", passed


def test_result(result_bundle: Path) -> tuple[str, bool]:
    summary = run_json(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result_bundle), "--compact"])
    if summary is None:
        return "test-results summary unavailable", False
    total = first_number(summary, ("totalTestCount", "totalTests"))
    passed = first_number(summary, ("passedTests", "passedTestCount"))
    failed = first_number(summary, ("failedTests", "failedTestCount"))
    skipped = first_number(summary, ("skippedTests", "skippedTestCount")) or 0
    result = str(summary.get("result", summary.get("status", ""))).lower()
    if total is None or passed is None:
        return "test-results summary has no counts", False
    text = f"passed={passed}; total={total}; failed={failed or 0}; skipped={skipped}; result={result or 'unknown'}"
    return text, total > 0 and passed == total and (failed or 0) == 0 and "fail" not in result


def warning_count(run_dir: Path) -> int:
    count = 0
    for path in (run_dir / "build.log", run_dir / "test.log", run_dir / "analyze.log"):
        if path.exists():
            count += len(re.findall(r"\bwarning:", path.read_text(encoding="utf-8", errors="replace"), re.IGNORECASE))
    return count


def swiftlint_status(run_dir: Path) -> tuple[str, bool]:
    exit_path = run_dir / "swiftlint.exit"
    if not exit_path.exists():
        return "not-run", False
    try:
        status = int(exit_path.read_text(encoding="utf-8").strip())
    except ValueError:
        return "invalid exit status", False
    return ("passed" if status == 0 else f"failed (exit {status})", status == 0)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-dir", required=True, type=Path)
    parser.add_argument("--device", required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--build-exit", required=True, type=int)
    parser.add_argument("--test-exit", required=True, type=int)
    parser.add_argument("--analyze-exit", required=True, type=int)
    parser.add_argument("--launch-exit", required=True, type=int)
    parser.add_argument("--screenshot-exit", required=True, type=int)
    args = parser.parse_args()
    run_dir = args.run_dir.resolve()
    report_path = Path("CI_REPORT.md")
    if platform.system() != "Darwin":
        report_path.write_text("# BPHealth CI 报告\n\n- 结果：未执行。此脚本只允许在真实 macOS runner 上生成 iOS 验证结论。\n", encoding="utf-8")
        return 2

    test_summary, tests_ok = test_result(run_dir / "test.xcresult") if (run_dir / "test.xcresult").exists() else ("result bundle missing", False)
    coverage, coverage_ok = coverage_result(run_dir / "test.xcresult") if (run_dir / "test.xcresult").exists() else ("result bundle missing", False)
    warnings = warning_count(run_dir)
    lint_text, lint_ok = swiftlint_status(run_dir)
    build_ok = args.build_exit == 0
    analyze_ok = args.analyze_exit == 0
    launch_ok = args.launch_exit == 0
    screenshot_ok = args.screenshot_exit == 0 and (run_dir / "dashboard.png").is_file() and (run_dir / "dashboard.png").stat().st_size > 0
    overall = all((build_ok, tests_ok and args.test_exit == 0, analyze_ok, launch_ok, screenshot_ok, coverage_ok, lint_ok, warnings == 0))
    lines = [
        "# BPHealth CI 报告", "", f"- 执行环境：macOS ({platform.mac_ver()[0] or 'unknown'})", f"- 模拟器 UDID：{args.device}",
        f"- Bundle Identifier：{args.bundle_id}", f"- Build：{'passed' if build_ok else f'failed (exit {args.build_exit})'}",
        f"- XCTest/UI Test：{'passed' if tests_ok and args.test_exit == 0 else f'failed (exit {args.test_exit}); {test_summary}'}",
        f"- xcodebuild analyze：{'passed' if analyze_ok else f'failed (exit {args.analyze_exit})'}",
        f"- SwiftLint：{lint_text}", f"- 编译/分析警告数：{warnings}", f"- XCTest 摘要：{test_summary}",
        f"- UI 截图：{'captured' if screenshot_ok else 'failed'}", f"- App 安装/启动：{'launched' if launch_ok else 'failed'}",
        f"- 覆盖率：{coverage}", f"- 最终质量门禁：{'PASS' if overall else 'FAIL'}", "",
        f"- 本轮原始工件：`{run_dir.as_posix()}`", "",
        "日志、`.xcresult` 和截图均来自本次 macOS runner；缺失工件会导致门禁失败。",
    ]
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    (run_dir / "CI_REPORT.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return 0 if overall else 1


if __name__ == "__main__":
    raise SystemExit(main())
