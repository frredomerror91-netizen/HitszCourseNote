#requires -Version 7.2
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Get-BytesHash([byte[]]$Bytes){[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))}
function Test-Inside([string]$Path,[string]$Root){$p=[IO.Path]::GetFullPath($Path);$r=[IO.Path]::GetFullPath($Root).TrimEnd('\','/');$p.StartsWith($r+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)}
function Assert-NoReparse([string]$Path){$p=[IO.Path]::GetFullPath($Path);while($p){if(Test-Path -LiteralPath $p){$i=Get-Item -LiteralPath $p -Force;if($i.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "拒绝目录链接/reparse: $Path"}};$parent=[IO.Path]::GetDirectoryName($p);if($parent -eq $p){break};$p=$parent}}
function Get-SafeDestination([pscustomobject]$Config,[string]$Relative){
 $r=$Relative.Replace('\','/');$parts=$r.Split('/')
 if([string]::IsNullOrWhiteSpace($r) -or [IO.Path]::IsPathRooted($r) -or $r -match '[:\x00-\x1f]' -or @($parts|Where-Object{$_ -in @('','..','.') -or $_.StartsWith('-') -or $_ -match '(?i)^(\.git|\.publish-state|tmp|temp|backup|backups|work)$' -or $_.EndsWith('.') -or $_.EndsWith(' ')}).Count){throw "不安全目标路径: $Relative"}
 if($parts.Count -lt 2 -or $parts[0] -notin @($Config.AllowedSubjects)){throw "目标不属于允许学科: $Relative"}
 $p=[IO.Path]::GetFullPath((Join-Path $Config.RepositoryRoot $r));if(-not (Test-Inside $p $Config.RepositoryRoot)){throw '目标越界'};Assert-NoReparse $p
 [pscustomobject]@{Relative=$r;Absolute=$p}
}
function Get-SafeSource([pscustomobject]$Config,[string]$Path){
 if(-not [IO.Path]::IsPathRooted($Path)){throw 'source 来源必须为绝对路径'}
 $p=[IO.Path]::GetFullPath($Path);if(-not @($Config.SourceRoots|Where-Object{Test-Inside $p $_}).Count){throw "source 来源越界: $Path"};Assert-NoReparse $p
 if(-not (Test-Path -LiteralPath $p -PathType Leaf)){throw "source 来源文件不存在: $Path"};if($p -match '(?i)[\\/](\.git|\.publish-state|tmp|temp|backups?)[\\/]' -or $p -match '(?i)\.(bak|tmp)$|\.original[-.]'){throw '拒绝临时/备份来源'}; $p
}
function Assert-PublicText([string]$Text){if($Text -match '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|(?im)(api[_-]?key|access[_-]?token|password)\s*[:=]\s*["'']?[A-Za-z0-9_/-]{16,}'){throw '发现疑似凭据/secret，发布停止'};if($Text -match '(?m)^\s*(TODO|TBD|待补充|undefined)\s*$'){throw '发现占位内容'}}
function Test-Markdown([string]$Text,[string]$Kind){
 if([string]::IsNullOrWhiteSpace($Text)){throw '空笔记'};Assert-PublicText $Text
 $lines=$Text -split '\r?\n';$fence=$null;$clean=[Collections.Generic.List[string]]::new()
 foreach($l in $lines){if($l -match '^\s{0,3}(`{3,}|~{3,})(.*)$'){$mark=$Matches[1];if($null -eq $fence){$fence=$mark}else{if($mark[0] -eq $fence[0] -and $mark.Length -ge $fence.Length -and [string]::IsNullOrWhiteSpace($Matches[2])){$fence=$null}};continue};if($null -eq $fence){$clean.Add($l)}};if($null -ne $fence){throw '代码围栏未闭合'}
 if($Kind -ne 'chapter-note'){return}
 $t=$clean -join "`n";if($t -match '(?m)^###\s+本章(?:要解决的问题|学完应会)\s*$'){throw '问题与成果须放进本章路线'}
 $chapters=[regex]::Matches($t,'(?ms)^## (?!#)([^\r\n]+)\r?\n(.*?)(?=^## (?!#)|\z)');$found=0
 foreach($c in $chapters){$b=$c.Groups[2].Value;if($c.Groups[1].Value -match '要学什么|学习地图|练习提示|常见问题|隔日复习|阅读资料|学习安排|参考答案|公式卡|核验|总览'){continue}
  $route=[regex]::Match($b,'(?m)^### 本章路线\s*$');if(-not $route.Success){throw "章节缺本章路线: $($c.Groups[1].Value)"};$found++
  $unit=[regex]::Match($b,'(?m)^### 学习单元\s*$');$summary=[regex]::Match($b,'(?m)^### 本章小结\s*$');$test=[regex]::Match($b,'(?m)^### 本章练习与检验\s*$')
  if(-not($unit.Success -and $summary.Success -and $test.Success) -or -not($route.Index -lt $unit.Index -and $unit.Index -lt $summary.Index -and $summary.Index -lt $test.Index)){throw '章节闭合顺序不正确'}
  $routeText=$b.Substring($route.Index,$unit.Index-$route.Index);if($routeText -notmatch '本章要解决的问题' -or $routeText -notmatch '本章学完应会'){throw '路线缺问题或成果'}
  $body=$b.Substring($unit.Index,$summary.Index-$unit.Index);$ex=[regex]::Matches($body,'(?m)^##### 小练习[：:]');if(-not $ex.Count){throw '章节缺小练习'}
  foreach($e in $ex){$before=$body.Substring(0,$e.Index);$heads=[regex]::Matches($before,'(?m)^#### (?!#)([^\r\n]+)');if(-not $heads.Count){throw '练习前缺具体知识标题/讲解'};$head=$heads[$heads.Count-1];if($head.Groups[1].Value -match '^(学习单元|知识点|基础检查|速查示例)$'){throw '知识标题过于泛化'}
   $prose=$before.Substring($head.Index+$head.Length);$prose=[regex]::Replace($prose,'(?s)\$\$.*?\$\$|\$[^\r\n$]*\$','');$prose=[regex]::Replace($prose,'(?m)^\s*[#|>].*$','');$prose=[regex]::Replace($prose,'(?ms)^##### 小练习.*','');if(([regex]::Matches($prose,'[\p{L}]')).Count -lt 40){throw '练习前知识讲解不足（启发式）'}
  }
 };if(-not $found){throw '章节型笔记没有可核验章节'}
}
function Get-LocalReferences([string]$Text){
 $items=[Collections.Generic.List[object]]::new()
 foreach($m in [regex]::Matches($Text,'(!?)\[[^\]\r\n]*\]\((<[^>]+>|[^)\r\n]+)\)')){$url=$m.Groups[2].Value.Trim();if($url.StartsWith('<')){$url=$url.Trim('<','>')}else{$url=$url -replace '\s+["''].*$',''};if($url -match '^https?://'){$items.Add([pscustomobject]@{Url=$url;External=$true;Image=($m.Groups[1].Value -eq '!')});continue};if($url -match '^#'){continue};if($url -match '^[A-Za-z]+:' -or $url.StartsWith('//')){throw "不允许的链接: $url"};$url=[Uri]::UnescapeDataString(($url -split '[?#]',2)[0]);if($url){$items.Add([pscustomobject]@{Url=$url;External=$false;Image=($m.Groups[1].Value -eq '!')})}}
 if($Text -match '(?im)^\s*\[[^\]]+\]:|<img\b|!\[[^\]]*\]\['){throw '暂不支持参考式链接或 HTML 图片；请改用内联 Markdown 链接'}
 $items.ToArray()
}
function Get-PublishSnapshot([pscustomobject]$Config,[pscustomobject]$Request){
 if($Config.SchemaVersion -ne 1 -or $Request.SchemaVersion -ne 1 -or $Request.ReviewCompleted -ne $true -or -not @($Request.Entries).Count){throw '缺少已完成内容审核的清单'}
 Assert-NoReparse $Config.RepositoryRoot
 $entries=[Collections.Generic.List[object]]::new();$dest=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 foreach($e in $Request.Entries){$src=Get-SafeSource $Config $e.SourcePath;$d=Get-SafeDestination $Config $e.DestinationPath;if(-not $dest.Add($d.Relative)){throw '目标路径重复/大小写碰撞'}
  if($e.Kind -notin @('chapter-note','general-note','image')){throw '未知文件类型'}
  $bytes=[IO.File]::ReadAllBytes($src);if($bytes.Length -gt 20MB){throw '单文件超过 20MB'};$hash=Get-BytesHash $bytes;if($hash -ne $e.ReviewedSha256){throw "审核摘要/hash不匹配: $src"}
  $text=$null;$ext=[IO.Path]::GetExtension($d.Relative).ToLowerInvariant()
  if($e.Kind -eq 'image'){if($ext -notin @('.png','.jpg','.jpeg','.webp','.gif','.svg') -or -not $bytes.Length){throw '图片类型/内容不允许'};if($ext -eq '.svg'){$text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes);Assert-PublicText $text;if($text -match '(?i)<script|<foreignObject|\bon\w+\s*=|(?:href|src)\s*=\s*["'']\s*(?:https?:|javascript:|data:)'){throw '拒绝包含主动内容/外部资源的 SVG'}}}
  else{if($ext -ne '.md'){throw '笔记必须是 .md'};$text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes);Test-Markdown $text $e.Kind}
  $entries.Add([pscustomobject]@{SourcePath=$src;DestinationPath=$d.Relative;AbsoluteDestination=$d.Absolute;ReviewedSha256=$hash;Bytes=$bytes;Text=$text;Kind=$e.Kind})
 }
 $external=[Collections.Generic.List[string]]::new()
 foreach($e in $entries){if($e.Kind -eq 'image'){continue};foreach($r in @(Get-LocalReferences $e.Text)){if($r.External){$external.Add($r.Url);continue};$source=Get-SafeSource $Config ([IO.Path]::GetFullPath((Join-Path (Split-Path $e.SourcePath) $r.Url)));$target=[IO.Path]::GetFullPath((Join-Path (Split-Path $e.AbsoluteDestination) $r.Url));if(-not(Test-Inside $target $Config.RepositoryRoot)){throw '本地引用目标越界'};Assert-NoReparse $target
  $matched=@($entries|Where-Object{$_.SourcePath -eq $source -and $_.AbsoluteDestination -eq $target});if($matched.Count -ne 1){throw "本地图片/引用未列入本次审核清单: $($r.Url)"}
 }}
 [pscustomobject]@{Entries=$entries.ToArray();Subjects=@($entries.DestinationPath|ForEach-Object{($_ -split '/')[0]}|Sort-Object -Unique);ExternalLinks=@($external|Sort-Object -Unique);ExternalLinkCheck='NotRun';ChangeSummary=@($entries.DestinationPath)}
}
function Test-PublishSnapshot([pscustomobject]$Snapshot){$errs=@();foreach($e in $Snapshot.Entries){if((Get-BytesHash ([IO.File]::ReadAllBytes($e.SourcePath))) -ne $e.ReviewedSha256){$errs+="审核后来源变化: $($e.SourcePath)"};Assert-NoReparse $e.SourcePath;Assert-NoReparse $e.AbsoluteDestination};$errs}
function Read-PublisherConfig([string]$Path){
 Assert-NoReparse $Path;$c=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json
 if($c.SchemaVersion -ne 1 -or $c.ExpectedRemote -ne 'https://github.com/frredomerror91-netizen/HitszCourseNote.git'){throw '配置版本/目标不符'}
 foreach($p in @($c.RepositoryRoot,$c.LogRoot)+@($c.SourceRoots)){if(-not [IO.Path]::IsPathRooted($p)){throw '配置根目录必须绝对路径'};Assert-NoReparse $p}
 if(-not @($c.SourceRoots).Count -or -not @($c.AllowedSubjects).Count -or $c.NetworkTimeoutSeconds -ne 30){throw '配置缺来源/学科或网络超时不是30秒'}
 foreach($s in $c.AllowedSubjects){if($s -match '[/\\:.\x00-\x1f]' -or $s.StartsWith('-') -or [string]::IsNullOrWhiteSpace($s)){throw '学科目录不安全'}}
 $c
}
Export-ModuleMember -Function Read-PublisherConfig, Get-BytesHash,Test-Inside,Assert-NoReparse,Get-SafeSource,Get-SafeDestination,Get-LocalReferences,Get-PublishSnapshot,Test-PublishSnapshot

