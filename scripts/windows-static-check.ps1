$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot ".."))
Set-Location $repo
$failures = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

function Require-File([string]$relativePath) {
    if (-not (Test-Path -LiteralPath $relativePath -PathType Leaf)) {
        $failures.Add("缺少文件：$relativePath")
    }
}

$required = @(
    "IMPLEMENTATION_PLAN.md", "README.md", "TEST_REPORT.md", "CI_REPORT.md",
    "Package.swift", "project.yml", "Config/Shared.xcconfig", ".gitattributes", ".swiftlint.yml",
    ".github/workflows/ios-ci.yml", "scripts/remote-verify.sh", "scripts/ci_report.py",
    "scripts/portable-boundary-check.py",
    "BPHealth/BPHealth.entitlements", "BPHealth/PrivacyInfo.xcprivacy", "BPHealthTests/BPHealthRuleTests.swift",
    "BPHealthTests/BPHealthUITests.swift", "docs/architecture.md",
    "docs/test-plan.md", "docs/medical-disclaimer.md",
    "BPHealth/Core/UseCases/ReadingUseCases.swift",
    "BPHealth/Core/Sync/ReadingSyncService.swift"
)
$required | ForEach-Object { Require-File $_ }

$swiftFiles = Get-ChildItem -Recurse -File -Filter "*.swift" BPHealth, BPHealthTests
foreach ($file in $swiftFiles) {
    $text = Get-Content -Raw -Encoding utf8 -LiteralPath $file.FullName
    if ($text -match "fatalError\(|try!|XCUIApplication!") {
        $failures.Add("Swift 禁用 API：$($file.FullName)")
    }
    $forceUnwrapPattern = '(?<=[A-Za-z0-9_\]\)])!(?=\s*[\.\[\(])|(?<=[A-Za-z0-9_\]\)])!\s*(?=$|[,;])|\bas!\b'
    if ($text -match $forceUnwrapPattern) {
        $failures.Add("Swift 强制解包：$($file.FullName)")
    }
    $open = ([regex]::Matches($text, "\{")).Count
    $close = ([regex]::Matches($text, "\}")).Count
    if ($open -ne $close) {
        $failures.Add("Swift 花括号不平衡：$($file.FullName) open=$open close=$close")
    }
}

$sourceFiles = Get-ChildItem -Recurse -File BPHealth
$disclaimer = "本应用不能替代医生诊断，如有不适请及时就医。"
$disclaimerHits = @($sourceFiles | Where-Object { (Get-Content -Raw -Encoding utf8 -LiteralPath $_.FullName) -like "*$disclaimer*" }).Count
if ($disclaimerHits -lt 3) {
    $failures.Add("医疗免责声明源码命中数不足：$disclaimerHits")
}

$viewText = Get-Content -Raw -Encoding utf8 -LiteralPath "BPHealth/Views/BPHealthViews.swift"
$pageDisclaimerReferences = ([regex]::Matches($viewText, "bpDisclaimer")).Count
if ($pageDisclaimerReferences -lt 7) {
    $failures.Add("分类/建议/导出相关页面免责声明引用不足：$pageDisclaimerReferences")
}
foreach ($page in @("DashboardView", "AddEditReadingView", "HistoryView", "TrendsView", "AdviceView", "ProfileView", "SettingsView", "ExportView", "PrivacyDisclaimerView")) {
    if ($viewText -notmatch "struct $page") { $failures.Add("缺少 UI 页面：$page") }
}
if ($viewText -match "BPClassificationText|BPAdviceText") {
    $failures.Add("UI 中存在绕过 RuleEngine 的旧分类/建议实现")
}
$uiTestText = Get-Content -Raw -Encoding utf8 -LiteralPath "BPHealthTests/BPHealthUITests.swift"
if ($uiTestText -match "if\s+[^\r\n]*\.exists|if\s+[^\r\n]*waitForExistence") {
    $failures.Add("UI 测试存在可跳过核心页面断言的条件分支")
}
$rulesText = Get-Content -Raw -Encoding utf8 -LiteralPath "BPHealth/Domain/Rules.swift"
if ($rulesText -notmatch "chinaReferenceThresholds") {
    $failures.Add("儿科默认百分位参考表缺失")
}
$modelText = Get-Content -Raw -Encoding utf8 -LiteralPath "BPHealth/Models/BPHealthModels.swift"
if ($modelText -notmatch "displayLevel\(language") {
    $failures.Add("分类结果缺少显式语言显示映射")
}
$projectText = Get-Content -Raw -Encoding utf8 -LiteralPath "project.yml"
if ($projectText -notmatch "BPHEALTH_BUNDLE_ID" -or $projectText -notmatch "BPHealth/Resources" -or $projectText -notmatch "PrivacyInfo\.xcprivacy") {
    $failures.Add("XcodeGen 配置缺少可覆盖 Bundle ID 或显式资源")
}

$entitlements = [xml](Get-Content -Raw -Encoding utf8 -LiteralPath "BPHealth/BPHealth.entitlements")
if (-not ($entitlements.plist.dict.key -contains "com.apple.developer.healthkit")) {
    $failures.Add("HealthKit entitlement 缺失")
}

$privacyManifest = [xml](Get-Content -Raw -Encoding utf8 -LiteralPath "BPHealth/PrivacyInfo.xcprivacy")
if (-not $privacyManifest.plist.dict) { $failures.Add("PrivacyInfo.xcprivacy plist 结构缺失") }
if (-not ($privacyManifest.plist.dict.key -contains "NSPrivacyTracking")) { $failures.Add("隐私清单缺少 NSPrivacyTracking") }
if (-not ($privacyManifest.plist.dict.key -contains "NSPrivacyCollectedDataTypes")) { $failures.Add("隐私清单缺少 NSPrivacyCollectedDataTypes") }

$textExtensions = @(".sh", ".yml", ".yaml", ".swift", ".md", ".json", ".strings", ".plist", ".xcprivacy", ".xcconfig", ".js", ".css", ".html", ".txt", ".py")
foreach ($file in (Get-ChildItem -Recurse -File | Where-Object { $_.FullName -notmatch "\\.git\\" })) {
    if (($textExtensions -contains $file.Extension.ToLowerInvariant()) -or $file.Name -in @(".gitignore", ".gitattributes", ".swiftlint.yml")) {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        if ($bytes -contains 13) { $failures.Add("文本文件含 CRLF/CR：$($file.FullName)") }
    }
}

$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) {
    & $node.Source --check app.js
    if ($LASTEXITCODE -ne 0) { $failures.Add("node --check app.js 失败") }
} else { $warnings.Add("node 不可用，跳过 JavaScript 语法检查") }

$bash = "C:\Program Files\Git\bin\bash.exe"
if (Test-Path -LiteralPath $bash) {
    & $bash -n scripts/remote-verify.sh
    if ($LASTEXITCODE -ne 0) { $failures.Add("bash -n scripts/remote-verify.sh 失败") }
} else { $warnings.Add("Git Bash 不可用，跳过 shell 语法检查") }

$python = Get-Command python -ErrorAction SilentlyContinue
if ($python) {
    & $python.Source scripts/portable-boundary-check.py
    if ($LASTEXITCODE -ne 0) { $failures.Add("portable-boundary-check.py 失败") }
} else { $warnings.Add("python 不可用，跳过便携边界检查") }

if ($failures.Count -gt 0) {
    Write-Error ("静态门禁失败：`n - " + ($failures -join "`n - "))
    exit 1
}
Write-Output "WINDOWS_STATIC_GATE=PASS"
if ($warnings.Count -gt 0) {
    Write-Output ("WARNINGS:`n - " + ($warnings -join "`n - "))
}
exit 0
