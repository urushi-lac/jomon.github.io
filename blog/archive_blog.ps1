# ========================================================
# 年またぎ＆メニュー自動スライド対応 スクリプト
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
    $year      = $matches[1]                     # 例: "2027"
    $monthDay  = "$($matches[2])-$($matches[3])" # 例: "01-15"
    $sectionId = "d$($matches[2])$($matches[3])" # 例: "d0115"
} else {
    Write-Error "更新日付（YYYY-MM-DD）が見つかりませんでした。"
    exit
}

$destPath = Join-Path $baseDir "$year.html"

# --- 【新機能】直近3年のメニューHTMLを動的に生成する関数 ---
function Update-YearMenus([string]$htmlContent, [string]$currentYear) {
    $y1 = [string]([int]$currentYear)
    $y2 = [string]([int]$currentYear - 1)
    $y3 = [string]([int]$currentYear - 2)

    # PC用メニューの置換
    $newPcMenu = @"
<ul id="menu">
            <li><a href="/blog/blog.html">Newest</a></li>
            <li><a href="/blog/$y1.html">$y1</a></li>
            <li><a href="/blog/$y2.html">$y2</a></li>
            <li><a href="/blog/$y3.html">$y3</a></li>
            <li><a href="/blog/archives.html">Archives</a></li>
          </ul>
"@
    $htmlContent = [regex]::Replace($htmlContent, '(?s)<ul id="menu">.*?</ul>', $newPcMenu)

    # モバイル用トグルメニューの置換
    $newMobileMenu = @"
<div class="toggle_contents">
          <h2><a href="/blog/blog.html">Newest</a></h2>
          <h2><a href="/blog/$y1.html">$y1</a></h2>
          <h2><a href="/blog/$y2.html">$y2</a></h2>
          <h2><a href="/blog/$y3.html">$y3</a></h2>
          <h2><a href="/blog/archives.html">Archives</a></h2>
        </div>
"@
    $htmlContent = [regex]::Replace($htmlContent, '(?s)<div class="toggle_contents">.*?</div>', $newMobileMenu)

    return $htmlContent
}

# 4. 年のページ（例: 2027.html）が存在しない場合は新規作成
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

    # 月別メニューを空枠（10個）に初期化
    $emptyMenus = ('<li><a href="#">-</a></li>`r`n          ' * 10).TrimEnd()
    $template = [regex]::Replace($template, '(?s)<ul id="menu1">.*?</ul>', "<ul id=`"menu1`">`r`n          $emptyMenus`r`n        </ul>")
    $template = [regex]::Replace($template, '(?s)<section id="d\d{4}">.*?</section>\s*', '')

    # 新しい年のメニュー（直近3年）に更新
    $template = Update-YearMenus $template $year

    [System.IO.File]::WriteAllText($destPath, $template, $enc)
    Write-Host "-> $year.html の新規作成とメニュー更新が完了しました。" -ForegroundColor Green

    # blog.html 側のメニューも新しい年（直近3年）に自動更新して保存
    $srcContent = Update-YearMenus $srcContent $year
    [System.IO.File]::WriteAllText($srcPath, $srcContent, $enc)
    Write-Host "-> blog.html のヘッダーメニューも最新年に更新しました。" -ForegroundColor Green
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

# 7. ナビゲーションメニュー（月別 menu1）の更新
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
