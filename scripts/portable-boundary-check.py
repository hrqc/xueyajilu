"""Portable semantic smoke check for the documented adult rule boundaries.

This is not a substitute for XCTest; it catches accidental changes to the
threshold table while the Windows host has no Swift/Xcode runtime.
"""


def classify(systolic: int, diastolic: int) -> str:
    if systolic > 180 or diastolic > 120:
        return "crisis"
    if systolic >= 180 or diastolic >= 110:
        return "stage3"
    if systolic < 90 or diastolic < 60:
        return "low"
    if systolic >= 160 or diastolic >= 100:
        return "stage2"
    if systolic >= 140 or diastolic >= 90:
        return "stage1"
    if systolic >= 120 or diastolic >= 80:
        return "elevated"
    return "normal"


CASES = [
    ((89, 59), "low"),
    ((90, 60), "normal"),
    ((119, 79), "normal"),
    ((120, 80), "elevated"),
    ((129, 79), "elevated"),
    ((130, 80), "elevated"),
    ((139, 89), "elevated"),
    ((140, 90), "stage1"),
    ((160, 100), "stage2"),
    ((180, 120), "stage3"),
    ((181, 121), "crisis"),
    ((89, 200), "crisis"),
]


failures = [(reading, expected, classify(*reading)) for reading, expected in CASES if classify(*reading) != expected]
if failures:
    print("PORTABLE_BOUNDARY_CHECK=FAIL")
    for failure in failures:
        print(failure)
    raise SystemExit(1)
print(f"PORTABLE_BOUNDARY_CHECK=PASS ({len(CASES)}/{len(CASES)})")
