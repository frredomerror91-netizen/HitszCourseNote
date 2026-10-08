#requires -Version 7.2
param([Parameter(Mandatory)][string]$ConfigPath,[Parameter(Mandatory)][string[]]$Notes,[Parameter(Mandatory)][string]$Subject,[ValidateSet('chapter-note','general-note')][string]$Kind='chapter-note',[switch]$ReviewCompleted,[Parameter(Mandatory)][string]$RequestPath)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Validation.psm1') -DisableNameChecking
$config=Read-PublisherConfig $ConfigPath
if(-not $ReviewCompleted){throw '必须先完成内容审核，再显式指定 -ReviewCompleted'}
if($Subject -notin @($config.AllowedSubjects)){throw '学科不在配置允许范围内'}
$entries=[Collections.Generic.List[object]]::new();$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($note in $Notes){$src=Get-SafeSource $config ([IO.Path]::GetFullPath($note));$dest="$Subject/$([IO.Path]::GetFileName($src))";$bytes=[IO.File]::ReadAllBytes($src);$text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
 if(-not $seen.Add($dest)){throw '笔记目标重复'};$entries.Add([pscustomobject]@{SourcePath=$src;DestinationPath=$dest;ReviewedSha256=(Get-BytesHash $bytes);Kind=$Kind})
 foreach($r in @(Get-LocalReferences $text)){if($r.External){continue};$image=Get-SafeSource $config ([IO.Path]::GetFullPath((Join-Path (Split-Path $src) $r.Url)));if([IO.Path]::GetExtension($image).ToLowerInvariant() -notin @('.png','.jpg','.jpeg','.webp','.gif','.svg')){continue};$targetAbs=[IO.Path]::GetFullPath((Join-Path (Join-Path $config.RepositoryRoot $Subject) $r.Url));$target=[IO.Path]::GetRelativePath($config.RepositoryRoot,$targetAbs).Replace('\','/');$null=Get-SafeDestination $config $target;if($seen.Add($target)){$entries.Add([pscustomobject]@{SourcePath=$image;DestinationPath=$target;ReviewedSha256=(Get-BytesHash ([IO.File]::ReadAllBytes($image)));Kind='image'})}}
}
$request=[pscustomobject]@{SchemaVersion=1;ReviewCompleted=$true;Entries=$entries.ToArray()};$snapshot=Get-PublishSnapshot $config $request
$state=[IO.Path]::GetFullPath((Join-Path $config.RepositoryRoot '.publish-state'));$requestFile=[IO.Path]::GetFullPath($RequestPath);if(-not(Test-Inside $requestFile $state)){throw '审核清单必须保存在本仓库 .publish-state 内'};Assert-NoReparse $requestFile
if(Test-Path -LiteralPath $requestFile){throw '清单文件已存在；请使用新的名称，不覆盖审核记录'}
[IO.Directory]::CreateDirectory((Split-Path $requestFile))|Out-Null;[IO.File]::WriteAllText($requestFile,($request|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
[pscustomobject]@{RequestPath=$requestFile;Files=$snapshot.Entries.DestinationPath;ExternalLinkCheck='NotRun'}|ConvertTo-Json -Depth 5
