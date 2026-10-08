#requires -Version 7.2
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Validation.psm1') -DisableNameChecking
function Get-FileFingerprint([string]$Path){if(Test-Path -LiteralPath $Path -PathType Leaf){Get-BytesHash ([IO.File]::ReadAllBytes($Path))}elseif(Test-Path -LiteralPath $Path){throw "路径不是文件: $Path"}else{'ABSENT'}}
function Write-VerifiedBytes([string]$Path,[byte[]]$Bytes,[string]$BeforeHash){
 Assert-NoReparse $Path
 if((Get-FileFingerprint $Path) -ne $BeforeHash){throw "写入冲突/变化: $Path"}
 [IO.Directory]::CreateDirectory((Split-Path $Path -Parent))|Out-Null
 $temp=$Path+'.publish-'+[guid]::NewGuid().ToString('N')+'.tmp'
 try{[IO.File]::WriteAllBytes($temp,$Bytes);if((Get-FileFingerprint $temp) -ne (Get-BytesHash $Bytes)){throw '临时文件回读失败'};if((Get-FileFingerprint $Path) -ne $BeforeHash){throw "并发变化: $Path"};[IO.File]::Move($temp,$Path,$true);if((Get-FileFingerprint $Path) -ne (Get-BytesHash $Bytes)){throw "写后核验失败: $Path"}}
 finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
}
function Merge-DateItems([string]$Text,[string]$Date,[string]$Category,[string[]]$Items){
 $missing=@($Items|Where-Object{-not $Text.Contains($_)});if(-not $missing.Count){return $Text}
 $m=[regex]::Match($Text,'(?m)^## '+[regex]::Escape($Date)+'\s*$');$append=$missing -join "`n"
 if(-not $m.Success){$first=[regex]::Match($Text,'(?m)^## ');$at=if($first.Success){$first.Index}else{$Text.Length};return $Text.Insert($at,"`n## $Date`n`n### $Category`n`n$append`n`n")}
 $next=[regex]::Match($Text.Substring($m.Index+$m.Length),'(?m)^## ');$end=if($next.Success){$m.Index+$m.Length+$next.Index}else{$Text.Length};$body=$Text.Substring($m.Index,$end-$m.Index);$c=[regex]::Match($body,'(?m)^### '+[regex]::Escape($Category)+'\s*$');$at=if($c.Success){$m.Index+$c.Index+$c.Length}else{$end};$new=if($c.Success){"`n`n$append`n"}else{"`n### $Category`n`n$append`n`n"};$Text.Insert($at,$new)
}
function Get-PublishLogPlan([pscustomobject]$Config,[pscustomobject]$Snapshot){
 $date=[TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTimeOffset]::UtcNow,'Asia/Shanghai').ToString('yyyy-MM-dd')
 $plans=[Collections.Generic.List[object]]::new();$targets=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
 $repoLog=Join-Path $Config.RepositoryRoot 'CHANGELOG.md';$global=Join-Path $Config.LogRoot 'DAILY_CHANGELOG.md';$daily=Join-Path $Config.LogRoot ("每日总结/$date.md")
 function AddTarget($Path,$Category,$Item,$Title,$Repo){if(-not $targets.ContainsKey($Path)){$targets[$Path]=[pscustomobject]@{Categories=@{};Title=$Title;Repository=$Repo}};if(-not $targets[$Path].Categories.ContainsKey($Category)){$targets[$Path].Categories[$Category]=@()};$targets[$Path].Categories[$Category]+=$Item}
 foreach($e in $Snapshot.Entries){
  $category=if($e.PSObject.Properties['ChangeKind']){$e.ChangeKind}elseif(Test-Path -LiteralPath $e.AbsoluteDestination){'修改'}else{'新增'}
  $name=$e.DestinationPath.Replace('`','');$item="- $category 学习资料：$name（内容摘要 $($e.ReviewedSha256.Substring(0,12))）。"
  AddTarget $repoLog $category $item '# 学习笔记更新日志' $true
  AddTarget $global $category ("- **HitszCourseNote**（$($Config.RepositoryRoot)）："+$item.Substring(2)) '# 每日总更新日志' $false
  AddTarget $daily $category ("- **HitszCourseNote**：$category 学习资料 $name（版本 $($e.ReviewedSha256.Substring(0,12))），上传状态以发布回执为准。") '# 每日成果总结' $false
  $root=@($Config.SourceRoots|Where-Object{Test-Inside $e.SourcePath $_}|Sort-Object Length -Descending)[0];$dir=Split-Path $e.SourcePath -Parent;$chosen=$null
  while($dir -and ($dir -eq $root -or (Test-Inside $dir $root))){if(Test-Path -LiteralPath (Join-Path $dir 'CHANGELOG.md')){$chosen=Join-Path $dir 'CHANGELOG.md';break};if($dir -eq $root){break};$dir=Split-Path $dir -Parent};if(-not $chosen){$chosen=Join-Path $root 'CHANGELOG.md'}
  if($chosen -ne $repoLog){AddTarget $chosen $category ("- $category 并审核 $([IO.Path]::GetFileName($e.SourcePath))（内容摘要 $($e.ReviewedSha256.Substring(0,12))）。") '# 更新日志' (Test-Inside $chosen $Config.RepositoryRoot)}
 }
 foreach($path in $targets.Keys){Assert-NoReparse $path;$before=Get-FileFingerprint $path;$old=if($before -eq 'ABSENT'){$targets[$path].Title+"`n"}else{[Text.UTF8Encoding]::new($false,$true).GetString([IO.File]::ReadAllBytes($path))};$new=$old
  foreach($cat in @('新增','修改')){if($targets[$path].Categories.ContainsKey($cat)){$new=Merge-DateItems $new $date $cat @($targets[$path].Categories[$cat]|Sort-Object -Unique)}}
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes($new);if((Get-BytesHash $bytes) -ne $before){$plans.Add([pscustomobject]@{Path=$path;BeforeSha256=$before;AfterBytes=$bytes;Repository=$targets[$path].Repository})}
 }
 [pscustomobject]@{Files=$plans.ToArray();RepositoryFiles=@($plans|Where-Object{$_.Repository}|ForEach-Object{[IO.Path]::GetRelativePath($Config.RepositoryRoot,$_.Path).Replace('\','/')})}
}
function Write-PublishLogPlan([pscustomobject]$Plan){
 foreach($f in $Plan.Files){if((Get-FileFingerprint $f.Path) -ne $f.BeforeSha256){throw "日志冲突/变化: $($f.Path)"};Assert-NoReparse $f.Path}
 $written=@();foreach($f in $Plan.Files){try{Write-VerifiedBytes $f.Path $f.AfterBytes $f.BeforeSha256;$written+=$f.Path}catch{throw "日志写入失败，已写入 $($written -join ', ')；错误 $($_.Exception.Message)"}};$written
}
Export-ModuleMember -Function Get-FileFingerprint,Write-VerifiedBytes,Get-PublishLogPlan,Write-PublishLogPlan

