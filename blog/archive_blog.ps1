# ========================================================
# ブログ・年代別・総合アーカイブ 完全自動同期スクリプト
# （あらゆるID名に完全対応版）
# ========================================================
$baseDir = $PSScriptRoot
$enc = [System.Text.UTF8Encoding]::new($false)
$siteBaseUrl = "https://urushi-watanabe.com/blog"

# --- 共通メニュー更新処理 ---
$script:UpdateMenus = {
    param($html, $currYear, $suffix)
    $y1 = [string]([int]$currYear)
    $y2 = [string]([int]$currYear - 1)
    $y3 = [string]([int]$currYear - 2)
    $topPage = if ($suffix -eq "") { "blog.html" } else { "blog$suffix.html" }
    $arcPage = if ($suffix -eq "") { "archives.html" } else { "archives$suffix.html" }

    $newPc = @"
<ul id="menu">
            <li><a href="/blog/$topPage">Newest</a></li>
            <li><a href="/blog/$y1$suffix.html">$y1</a></li>
            <li><a href="/blog/$y2$suffix.html">$y2</a></li>
            <li><a href="/blog/$y3$suffix.html">$y3</a></li>
            <li><a href="/blog/$arcPage">Archives</a></li>
          </ul>
"@
    $html = [regex]::Replace($html, '(?s)<ul id="menu">.*?</ul>', $newPc)

    $newMobile = @"
<div class="toggle_contents">
          <h2><a href="/blog/$topPage">Newest</a></h2>
          <h2><a href="/blog/$y1$suffix.html">$y1</a></h2>
          <h2><a href="/blog/$y2$suffix.html">$y2</a></h2>
          <h2><a href="/blog/$y3$suffix.html">$y3</a></h2>
          <h2><a href="/blog/$arcPage">Archives</a></h2>
        </div>
"@
    return [regex]::Replace($html, '(?s)<div class="toggle_contents">.*?</div>', $newMobile)
}

# --- archives.html / archives-e.html への追記＆新年度作成関数 ---
function Update-Archives([string]$LangSuffix, [string]$year, [string]$fullDate, [string]$sectionId, [string]$title) {
    $arcFileName = if ($LangSuffix -eq "") { "archives.html" } else { "archives$LangSuffix.html" }
    $arcPath     = Join-Path $baseDir $arcFileName
    if (-not (Test-Path $arcPath)) { return }

    $arcContent = [System.IO.File]::ReadAllText($arcPath, [System.Text.Encoding]::UTF8)

    # 既にこの記事タイトルが存在すればスキップ
    if ($arcContent.Contains($title)) { return }

    $destFileName = "$year$LangSuffix.html"
    $newListItem  = "        <li><a href=`"/blog/$destFileName#$sectionId`"><span class=`"mgr-50`">$fullDate</span>$title</a></li>"

    # 新年でまだその年のセクションが存在しない場合、セクション枠を自動作成
    if ($arcContent -notmatch "(?i)<section\b[^>]*\bid=[`"']archive-$year[`"']") {
        Write-Host "【総合目録更新】$arcFileName に $year 年のセクションを新規作成します..." -ForegroundColor Yellow
        $prevYear = [string]([int]$year - 1)

        $newSectionBlock = @"
  <!-- $year年アーカイブ -->
  <section id="archive-$year">
    <h1><a href="/blog/$destFileName">$year</a></h1>
    <div class="link">
      <ul class="archive-list">
      </ul>
    </div>
  </section>

"@
        if ($arcContent -match "(?i)<!--\s*$prevYear.*?-->") {
            $arcContent = [regex]::Replace($arcContent, "(?i)(<!--\s*$prevYear.*?-->)", "$newSectionBlock  `$1", 1)
        } else {
            $arcContent = [regex]::Replace($arcContent, '(</header>)', "`$1`r`n`r`n$newSectionBlock", 1)
        }

        $arcContent = & $script:UpdateMenus $arcContent $year $LangSuffix
    }

    # 該当年の <ul class="archive-list"> の末尾に記事リンクを追加
    $pattern = "(?si)(<section\b[^>]*\bid=[`"']archive-$year[`"'].*?<ul\b[^>]*class=[`"']archive-list[`"'][^>]*>)(.*?)(</ul>)"
    if ($arcContent -match $pattern) {
        $arcContent = [regex]::Replace($arcContent, $pattern, "`$1`$2$newListItem`r`n      `$3", 1)
        [System.IO.File]::WriteAllText($arcPath, $arcContent, $enc)
        Write-Host "✔ [$arcFileName] に記事目録を追加しました ($fullDate)" -ForegroundColor Green
    }
}

# --- 共通のアーカイブ処理 ---
function Sync-Blog([string]$LangSuffix) {
    $srcFileName = if ($LangSuffix -eq "") { "blog.html" } else { "blog$LangSuffix.html" }
    $srcPath     = Join-Path $baseDir $srcFileName

    if (-not (Test-Path $srcPath)) {
        Write-Warning "$srcFileName が見つからないためスキップします。"
        return
    }

    $srcContent = [System.IO.File]::ReadAllText($srcPath, [System.Text.Encoding]::UTF8)

    # ★ ID名に依存せず、ページ内の最初の <section>...</section> を最新記事として取得
    $sectionRegex = '(?si)<section\b[^>]*>.*?</section>'
    $match = [regex]::Match($srcContent, $sectionRegex)
    if (-not $match.Success) {
        Write-Warning "$srcFileName に最新記事セクション（<section>）が見つかりませんでした。"
        return
    }
    $extractedHtml = $match.Value

    # 元のIDを取得（例: "old-lacquer-tree" や "top"）
    $originalId = ""
    if ($extractedHtml -match '(?i)\bid=["'']([^"'']+)["'']') {
        $originalId = $matches[1]
    }

    # 日付判定
    $datePattern = '<h5>\s*(\d{4})-(\d{2})-(\d{2})'
    if ($extractedHtml -match $datePattern) {
        $year      = $matches[1]
        $fullDate  = "$($matches[1])-$($matches[2])-$($matches[3])"
        $monthDay  = "$($matches[2])-$($matches[3])"
        # 元のIDが "top" や空の場合は日付IDにし、固有IDがあればそのまま使う
        if ($originalId -eq "top" -or [string]::IsNullOrWhiteSpace($originalId)) {
            $sectionId = "d$($matches[2])$($matches[3])"
        } else {
            $sectionId = $originalId
        }
    } else {
        Write-Warning "$srcFileName から更新日付（YYYY-MM-DD）が取得できませんでした。"
        return
    }

    $destFileName = "$year$LangSuffix.html"
    $destPath     = Join-Path $baseDir $destFileName

    # タイトル取得
    $title = ""
    if ($extractedHtml -match '<h1>(.*?)</h1>') {
        $title = $matches[1]
    }

    # 年越し新規作成
    if (-not (Test-Path $destPath)) {
        $prevYear = [string]([int]$year - 1)
        $prevPath = Join-Path $baseDir "$prevYear$LangSuffix.html"

        if (-not (Test-Path $prevPath)) {
            Write-Error "前年ファイル（$prevPath）が見つかりません。"
            return
        }

        Write-Host "【新年の検出】$destFileName を新しく自動作成します..." -ForegroundColor Yellow
        $tmpl = [System.IO.File]::ReadAllText($prevPath, [System.Text.Encoding]::UTF8)
        $tmpl = $tmpl.Replace($prevYear, $year)

        $newUrl = "$siteBaseUrl/$destFileName"
        $tmpl = [regex]::Replace($tmpl, '(?i)<meta\s+property="og:url"\s+content="[^"]+"', "<meta property=`"og:url`" content=`"$newUrl`"")
        $tmpl = [regex]::Replace($tmpl, '(?i)<link\s+rel="canonical"\s+href="[^"]+"', "<link rel=`"canonical`" href=`"$newUrl`"")

        $emptyMenus = ('<li><a href="#">-</a></li>`r`n          ' * 10).TrimEnd()
        $tmpl = [regex]::Replace($tmpl, '(?s)<ul id="menu1">.*?</ul>', "<ul id=`"menu1`">`r`n          $emptyMenus`r`n        </ul>")
        $tmpl = [regex]::Replace($tmpl, '(?si)<section\b[^>]*>.*?</section>\s*', '')

        $tmpl = & $script:UpdateMenus $tmpl $year $LangSuffix
        [System.IO.File]::WriteAllText($destPath, $tmpl, $enc)

        $srcContent = & $script:UpdateMenus $srcContent $year $LangSuffix
        [System.IO.File]::WriteAllText($srcPath, $srcContent, $enc)
        Write-Host "-> $destFileName の作成（og:url・メニュー更新完了）" -ForegroundColor Green
    }

    $destContent = [System.IO.File]::ReadAllText($destPath, [System.Text.Encoding]::UTF8)

    # 重複チェック
    if ($destContent.Contains($title)) {
        Write-Host "・[$srcFileName] 既に最新記事が年別ページにアーカイブ済みです。" -ForegroundColor DarkGray
        Update-Archives $LangSuffix $year $fullDate $sectionId $title
        return
    }

    # HTML加工（「過去記事へ」リンク削除 ＆ 適切なIDの付与）
    $cleanHtml = [regex]::Replace($extractedHtml, '(?si)\s*<p3>\s*<a href="[^"]*".*?</p3>', '')
    $cleanHtml = [regex]::Replace($cleanHtml, '(?i)<section\b[^>]*>', "<section id=`"$sectionId`">", 1)

    # 月別メニュー更新
    $emptyLinkRegex = [regex]'(?i)<li>\s*<a\s+href="#"\s*>\s*-\s*</a>\s*</li>'
    if ($emptyLinkRegex.IsMatch($destContent)) {
        $destContent = $emptyLinkRegex.Replace($destContent, "<li><a href=`"#$sectionId`">$monthDay</a></li>", 1)
    }

    # 記事挿入
    if ($destContent -match '</section>') {
        $lastPos = $destContent.LastIndexOf("</section>") + "</section>".Length
        $destContent = $destContent.Insert($lastPos, "`r`n`r`n    $cleanHtml")
    } else {
        $destContent = [regex]::Replace($destContent, '(</nav>\s*</header>)', "`$1`r`n`r`n    $cleanHtml", 1)
    }

    [System.IO.File]::WriteAllText($destPath, $destContent, $enc)
    Write-Host "✔ [$srcFileName -> $destFileName] 年別ページへ追加完了 (#$sectionId)" -ForegroundColor Green

    # archives への追加
    Update-Archives $LangSuffix $year $fullDate $sectionId $title
}

# 実行
Write-Host "=== ブログ更新・完全同期を開始します ===" -ForegroundColor Cyan
Sync-Blog -LangSuffix ""
Sync-Blog -LangSuffix "-e"
Write-Host "=== すべての更新が完了しました ===" -ForegroundColor Cyan
