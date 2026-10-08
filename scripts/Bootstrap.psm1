#requires -Version 7.2
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Validation.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'PublishLogs.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'GitPublish.psm1') -DisableNameChecking
function Get-BootstrapFiles { @('.gitignore','README.md','CHANGELOG.md','AGENTS.md','publisher.example.json','scripts/Validation.psm1','scripts/PublishLogs.psm1','scripts/GitPublish.psm1','scripts/Bootstrap.psm1','scripts/New-PublishRequest.ps1','scripts/Publish-StudyNotes.ps1','scripts/Initialize-Publisher.ps1','tests/Test-StudyPublisher.ps1') }
function BGit($Root,[string[]]$ArgsList){$r=Invoke-GitChecked $Root $ArgsList 30;if($r.ExitCode){throw "Git初始化失败: $($r.Stderr)"};$r.Stdout.Trim()}
function Write-InstallState($Dest,$State){$p=Join-Path $Dest '.publish-state/install.json';Write-VerifiedBytes $p ([Text.UTF8Encoding]::new($false).GetBytes(($State|ConvertTo-Json -Depth 8))) (Get-FileFingerprint $p)}
function Install-StudyPublisher {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$Destination,[Parameter(Mandatory)][string]$RemoteUrl,[Parameter(Mandatory)][string]$ToolPackagePath,[switch]$DryRun,[switch]$Execute,[switch]$PublishBootstrap,[switch]$ResumeInstallation)
 if($DryRun -eq $Execute){throw '必须选择 DryRun 或 Execute'}
 $dest=[IO.Path]::GetFullPath($Destination);$package=[IO.Path]::GetFullPath($ToolPackagePath);Assert-NoReparse $dest;Assert-NoReparse $package
 if(Test-Inside $dest $package){throw '目标不能位于工具包内'}
 $files=Get-BootstrapFiles;foreach($f in $files){if(-not(Test-Path -LiteralPath (Join-Path $package $f) -PathType Leaf)){throw "工具包缺文件: $f"};Assert-NoReparse (Join-Path $package $f)}
 if(-not $ResumeInstallation -and (Test-Path -LiteralPath $dest)){throw '目标目录已存在，拒绝覆盖'}
 if($DryRun){return [pscustomobject]@{Status='DryRun';Destination=$dest;Remote=$RemoteUrl;Files=$files;InitialNotesMigrated=$false}}
 $stateFile=Join-Path $dest '.publish-state/install.json';$cfgFile=Join-Path $dest 'publisher.local.json'
 if($ResumeInstallation){if(-not(Test-Path -LiteralPath $stateFile)){throw '无本机安装回执，不能续接'};Assert-NoReparse $stateFile;$state=Get-Content -LiteralPath $stateFile -Raw|ConvertFrom-Json;if($state.RemoteUrl -ne $RemoteUrl){throw '安装回执远端不符'};foreach($f in $state.Manifest){if((Get-FileFingerprint (Join-Path $dest $f.Path)) -ne $f.Sha256){throw "安装工具被修改: $($f.Path)"}}}
 else{
  $probe=Invoke-GitChecked $package @('ls-remote',$RemoteUrl) 30;if($probe.ExitCode){throw "远端检查失败: $($probe.Stderr)"};if($probe.Stdout.Trim()){throw '远端不再是空仓库；不自动初始化/迁移'}
  [IO.Directory]::CreateDirectory((Split-Path $dest -Parent))|Out-Null;$null=BGit (Split-Path $dest -Parent) @('clone','--',$RemoteUrl,$dest);$null=BGit $dest @('symbolic-ref','HEAD','refs/heads/main')
  foreach($f in $files){$target=Join-Path $dest $f;[IO.Directory]::CreateDirectory((Split-Path $target))|Out-Null;[IO.File]::Copy((Join-Path $package $f),$target,$false)}
  $config=Get-Content -LiteralPath (Join-Path $package 'publisher.example.json') -Raw|ConvertFrom-Json;$config.RepositoryRoot=$dest;$config.ExpectedRemote=$RemoteUrl;$config.SourceRoots=@($dest)+@($config.SourceRoots|Where-Object{Test-Path -LiteralPath $_ -PathType Container});$config|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $cfgFile -Encoding utf8
  $manifest=@($files|ForEach-Object{[pscustomobject]@{Path=$_;Sha256=(Get-FileFingerprint (Join-Path $dest $_))}})
  $state=[pscustomobject]@{SchemaVersion=1;RemoteUrl=$RemoteUrl;Manifest=$manifest;BootstrapCommitId=$null;Status='Installed'};Write-InstallState $dest $state
 }
 $cfg=Get-Content -LiteralPath $cfgFile -Raw|ConvertFrom-Json
 if($cfg.RepositoryRoot -ne $dest -or $cfg.ExpectedRemote -ne $RemoteUrl){throw '本地配置与安装对象不符'};Assert-Repository $cfg
 if(-not $PublishBootstrap){return [pscustomobject]@{Status='Installed';Destination=$dest;Files=$files;Errors=@();CommitId=$state.BootstrapCommitId}}
 $lock=$null;$id=$state.BootstrapCommitId
 try{
  $lock=[IO.File]::Open((Join-Path $dest '.publish-state/publisher.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);Assert-Repository $cfg
  $probe=Invoke-GitChecked $dest @('ls-remote','origin') 30;if($probe.ExitCode){throw '不能核对远端'}
  if($id){if((BGit $dest @('rev-parse','HEAD')) -ne $id){throw '本地HEAD不等于初始化回执'};if($probe.Stdout.Trim() -and (Get-RemoteHead $cfg) -ne $id){throw '远端出现其他历史；停止'}
   $committed=@((BGit $dest @('ls-tree','-r','--name-only','HEAD')) -split '\r?\n');if(@(Compare-Object @($files|Sort-Object) @($committed|Sort-Object)).Count){throw '初始提交文件集合不符'}
   foreach($f in $files){$oid=BGit $dest @('hash-object','--no-filters','--',(Join-Path $dest $f));$tree=BGit $dest @('ls-tree','HEAD','--',$f);if($tree -notmatch ([regex]::Escape($oid)+'\t')){throw '初始提交对象摘要不符'}}
  }else{
   if($probe.Stdout.Trim()){throw '空仓库状态已改变，停止'};$existing=Invoke-GitChecked $dest @('rev-parse','--verify','HEAD') 30;if($existing.ExitCode -eq 0){throw '出现未记录的本地提交'}
   $null=BGit $dest (@('-c','core.autocrlf=false','add','--')+$files);$indexed=@((BGit $dest @('diff','--cached','--name-only')) -split '\r?\n');if(@(Compare-Object @($files|Sort-Object) @($indexed|Sort-Object)).Count){throw '初始化暂存集合不符'}
   $null=BGit $dest @('commit','-m','chore: initialize checked study-note publisher');$id=BGit $dest @('rev-parse','HEAD');$state.BootstrapCommitId=$id;$state.Status='CommittedNotPushed';Write-InstallState $dest $state
   $committed=@((BGit $dest @('ls-tree','-r','--name-only','HEAD')) -split '\r?\n');if(@(Compare-Object @($files|Sort-Object) @($committed|Sort-Object)).Count){throw '钩子改变初始提交文件集合，停止'}
  }
  foreach($f in $state.Manifest){$path=Join-Path $dest $f.Path;if((Get-FileFingerprint $path) -ne $f.Sha256){throw '提交钩子/外部编辑改变已审核工具，停止上传'};$oid=BGit $dest @('hash-object','--no-filters','--',$path);$tree=BGit $dest @('ls-tree','HEAD','--',$f.Path);if($tree -notmatch ([regex]::Escape($oid)+'\t')){throw '初始提交对象不是审核文件，停止上传'}}
  if((Get-RemoteHead $cfg) -ne $id){$push=Invoke-GitChecked $dest @('push','-u','origin','HEAD:refs/heads/main') 30}else{$push=[pscustomobject]@{ExitCode=0;Stderr=''}}
  try{$remote=Get-RemoteHead $cfg}catch{$state.Status='Unknown';Write-InstallState $dest $state;return New-Result 'Unknown' $id $files @($_.Exception.Message)}
  if($remote -eq $id){$state.Status='Pushed';Write-InstallState $dest $state;New-Result 'Pushed' $id $files @()}else{$state.Status='CommittedNotPushed';Write-InstallState $dest $state;New-Result 'CommittedNotPushed' $id $files @($push.Stderr)}
 }catch{if($id){New-Result 'CommittedNotPushed' $id $files @($_.Exception.Message)}else{New-Result 'Blocked' $null $files @($_.Exception.Message)}}finally{if($lock){$lock.Dispose()}}
}
Export-ModuleMember -Function Install-StudyPublisher,Get-BootstrapFiles


