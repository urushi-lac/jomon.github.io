# ========================================================
# 年またぎ対応 記事アーカイブ自動化スクリプト【安全版】
# ========================================================
$baseDir = $PSScriptRoot
$srcPath = Join-Path $baseDir "blog.html"

if (-not (Test-Path $srcPath)) {
    Write-Error "$srcPath が見つかりません。"
    exit
}

$enc = [System.Text.UTF8Encoding]::new($false)

# 1. blog.html の読み込み
$srcContent = [System.IO.File]::ReadAllText($srcPath, [System.Text.Encoding]::UTF8)

# 2. 最新記事の取得
$sectionRegex = '(?s)<section id="top">.*?</section>'
$match = [regex]::Match($srcContent, $sectionRegex)
if (-not $match.Success) {
    Write-Error 'blog.html に section id="top" が見つかりませんでした。'
    exit
}
$extractedHtml = $match.Value

# 3. 日付から「年」「月-日」を自動判定
$datePattern = '<h5>(\d{4})-(\d{2})-(\d{2})'
if ($extractedHtml -match $datePattern) {
    $year      = $matches[1]
    $monthDay  = "$($matches[2])-$($matches[3])"
    $sectionId = "d$($matches[2])$($matches[3])"
} else {
    Write-Error "更新日付（YYYY-MM-DD）が見つかりませんでした。"
    exit
}

$destPath = Join-Path $baseDir "$year.html"

# 4. 年のページ（例: 2027.html）が存在しない場合は前年を元に新規作成
if (-not (Test-Path $destPath)) {
    $prevYear = [string]([int]$year - 1)
    $prevPath = Join-Path $baseDir "$prevYear.html"

    if (-not (Test-Path $prevPath)) {
        Write-Error "雛形となる前年のファイル（$prevPath）が見つかりません。"
        exit
    }

    Write-Host "【新年の検出】$year.html を新しく自動作成します..." -ForegroundColor Yellow
    $template = [System.IO.File]::ReadAllText($prevPath, [System.Text.Encoding]::UTF8)
    $template = $template.Replace($prevYear, $year)

    $emptyMenus = ('<li><a href="#">-</a></li>`r`n          ' * 10).TrimEnd()
    $template = [regex]::Replace($template, '(?s)<ul id="menu1">.*?</ul>', "<ul id=`"menu1`">`r`n          $emptyMenus`r`n        </ul>")
    $template = [regex]::Replace($template, '(?s)<section id="d\d{4}">.*?</section>\s*', '')

    [System.IO.File]::WriteAllText($destPath, $template, $enc)
    Write-Host "-> $year.html の新規テンプレートを作成しました。" -ForegroundColor Green
}

# 5. 年別アーカイブページの読み込み
$destContent = [System.IO.File]::ReadAllText($destPath, [System.Text.Encoding]::UTF8)

# 記事の重複チェック
if ($extractedHtml -match '<h1>(.*?)</h1>') {
    $title = $matches[1]
    if ($destContent.Contains($title)) {
        Write-Warning "この記事（$title）はすでに $year.html に存在します。処理を中断しました。"
        exit
    }
}

# 6. 記事HTMLの加工
$cleanHtml = [regex]::Replace($extractedHtml, '(?s)\s*<p3>\s*<a href="(?:\.\./)?blog/.*?\.html".*?</p3>', '')
$cleanHtml = [regex]::Replace($cleanHtml, '<section id="top">', "<section id=`"$sectionId`">")

# 7. ナビゲーションメニューの更新
$emptyLinkRegex = [regex]'(?i)<li>\s*<a\s+href="#"\s*>\s*-\s*</a>\s*</li>'
if ($emptyLinkRegex.IsMatch($destContent)) {
    $newMenuItem = "<li><a href=`"#$sectionId`">$monthDay</a></li>"
    $destContent = $emptyLinkRegex.Replace($destContent, $newMenuItem, 1)
}

# 8. 記事の挿入
if ($destContent -match '</section>') {
    $lastPos = $destContent.LastIndexOf("</section>") + "</section>".Length
    $destContent = $destContent.Insert($lastPos, "`r`n`r`n    $cleanHtml")
} else {
    $destContent = [regex]::Replace($destContent, '(</nav>\s*</header>)', "`$1`r`n`r`n    $cleanHtml", 1)
}

# 9. 保存
[System.IO.File]::WriteAllText($destPath, $destContent, $enc)

Write-Host "アーカイブ完了！" -ForegroundColor Green
Write-Host "対象ファイル: $year.html" -ForegroundColor Cyan
Write-Host "追加メニュー: $monthDay (#$sectionId)" -ForegroundColor Cyan
