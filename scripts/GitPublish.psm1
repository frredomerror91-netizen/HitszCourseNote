#requires -Version 7.2
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Validation.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'PublishLogs.psm1') -DisableNameChecking
$script:SimulateAcceptedTimeout=$false
$script:SimulateReceiptFailure=$false
function Invoke-GitChecked([string]$Root,[string[]]$Arguments,[int]$TimeoutSeconds=30){
 $si=[Diagnostics.ProcessStartInfo]::new();$si.FileName='git';$si.WorkingDirectory=$Root;$si.UseShellExecute=$false;$si.CreateNoWindow=$true;$si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true;$si.StandardOutputEncoding=[Text.UTF8Encoding]::new($false);$si.StandardErrorEncoding=[Text.UTF8Encoding]::new($false)
 foreach($a in @('-c','core.quotepath=false')+$Arguments){$si.ArgumentList.Add($a)};$si.Environment['GIT_TERMINAL_PROMPT']='0';$si.Environment['GCM_INTERACTIVE']='Never';$si.Environment['GIT_OPTIONAL_LOCKS']='0'
 $p=[Diagnostics.Process]::new();$p.StartInfo=$si
 try{$null=$p.Start();$out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync();if(-not $p.WaitForExit($TimeoutSeconds*1000)){try{$p.Kill($true)}catch{};$p.WaitForExit();return [pscustomobject]@{ExitCode=124;Stdout=$out.GetAwaiter().GetResult();Stderr='Git调用超时';TimedOut=$true}};[pscustomobject]@{ExitCode=$p.ExitCode;Stdout=$out.GetAwaiter().GetResult();Stderr=$err.GetAwaiter().GetResult();TimedOut=$false}}
 finally{$p.Dispose()}
}
function Git([pscustomobject]$C,[string[]]$ArgsList){$r=Invoke-GitChecked $C.RepositoryRoot $ArgsList $C.NetworkTimeoutSeconds;if($r.ExitCode){throw "Git失败 [$($ArgsList[0])]：$($r.Stderr)"};$r.Stdout.Trim()}
function Assert-Repository([pscustomobject]$C){
 Assert-NoReparse $C.RepositoryRoot;Assert-NoReparse (Join-Path $C.RepositoryRoot '.git');if(-not(Test-Path -LiteralPath (Join-Path $C.RepositoryRoot '.git') -PathType Container)){throw '需要独立clone目录，不支持共享worktree'};$actual=Git $C @('rev-parse','--show-toplevel');if([IO.Path]::GetFullPath($actual) -ne [IO.Path]::GetFullPath($C.RepositoryRoot)){throw 'Git仓库根目录不符'}
 if((Git $C @('branch','--show-current')) -ne 'main'){throw '必须在 main'};$remote=Git $C @('remote','get-url','origin');$push=Git $C @('remote','get-url','--push','origin');if($remote -ne $C.ExpectedRemote -or $push -ne $C.ExpectedRemote){throw 'Git远端不符'}
 $pushUrls=@((Git $C @('remote','get-url','--push','--all','origin')) -split '\r?\n');if($pushUrls.Count -ne 1){throw '拒绝多个推送远端'}
 if(Git $C @('diff','--cached','--name-only')){throw '存在其他暂存内容'}
 foreach($marker in @('MERGE_HEAD','REBASE_HEAD','CHERRY_PICK_HEAD','BISECT_LOG')){if(Test-Path -LiteralPath (Join-Path $C.RepositoryRoot ".git/$marker")){throw 'Git存在未完成操作'}}
}
function Get-RemoteHead([pscustomobject]$C){$r=Invoke-GitChecked $C.RepositoryRoot @('ls-remote','origin','refs/heads/main') $C.NetworkTimeoutSeconds;if($r.ExitCode){throw "查询远端失败: $($r.Stderr)"};$s=$r.Stdout.Trim();if(-not $s){return $null};if($s -notmatch '^([a-f0-9]{40,64})\s+refs/heads/main$'){throw '远端 main 输出异常'};$Matches[1]}
function Confirm-RemoteCommit([pscustomobject]$C,[string]$Commit){
 $head=Get-RemoteHead $C;if($head -eq $Commit){return $true};if(-not $head){return $false};$null=Git $C @('fetch','--no-tags','origin','refs/heads/main');$r=Invoke-GitChecked $C.RepositoryRoot @('merge-base','--is-ancestor',$Commit,'FETCH_HEAD') $C.NetworkTimeoutSeconds;if($r.ExitCode -gt 1){throw '无法核对远端包含关系'};$r.ExitCode -eq 0
}
function Enter-PublishLock([pscustomobject]$C){$state=Join-Path $C.RepositoryRoot '.publish-state';Assert-NoReparse $state;[IO.Directory]::CreateDirectory($state)|Out-Null;[IO.File]::Open((Join-Path $state 'publisher.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
function New-Result([string]$Status,[string]$Commit,[string[]]$Files,[string[]]$Errors){[pscustomobject]@{Status=$Status;CommitId=$Commit;Files=@($Files);Errors=@($Errors)}}
function Write-Receipt([pscustomobject]$C,[pscustomobject]$Receipt){if($script:SimulateReceiptFailure){throw '模拟回执写入失败'};$p=Join-Path $C.RepositoryRoot '.publish-state/last-publish.json';$b=[Text.UTF8Encoding]::new($false).GetBytes(($Receipt|ConvertTo-Json -Depth 8));Write-VerifiedBytes $p $b (Get-FileFingerprint $p)}
function Push-AndConfirm([pscustomobject]$C,[pscustomobject]$Receipt){
 $r=Invoke-GitChecked $C.RepositoryRoot @('push','origin','HEAD:refs/heads/main') $C.NetworkTimeoutSeconds;if($script:SimulateAcceptedTimeout){$r=[pscustomobject]@{ExitCode=124;Stdout='';Stderr='模拟超时'}}
 try{$ok=Confirm-RemoteCommit $C $Receipt.CommitId}catch{$Receipt.Status='Unknown';try{Write-Receipt $C $Receipt}catch{};return New-Result 'Unknown' $Receipt.CommitId $Receipt.Files @($_.Exception.Message)}
 if($ok){$Receipt.Status='Pushed';try{Write-Receipt $C $Receipt}catch{return New-Result 'Pushed' $Receipt.CommitId $Receipt.Files @('远端已核对，但本地回执更新失败')};return New-Result 'Pushed' $Receipt.CommitId $Receipt.Files @()}
 $Receipt.Status='CommittedNotPushed';Write-Receipt $C $Receipt;New-Result 'CommittedNotPushed' $Receipt.CommitId $Receipt.Files @($r.Stderr,'远端未包含本次提交；没有强推')
}
function Get-IndexRecord([pscustomobject]$C,[string]$Path){$r=Git $C @('ls-files','--stage','--',$Path);if($r -notmatch '^(100644|100755) ([a-f0-9]{40,64}) 0\t'){throw "暂存内容/类型异常: $Path"};$Matches[2]}
function Assert-ExactCommit([pscustomobject]$C,[pscustomobject]$Receipt){
 $id=Git $C @('rev-parse','HEAD');if($id -ne $Receipt.CommitId){throw 'HEAD不是本次回执提交'}
 $parent=Git $C @('rev-parse','HEAD^');if($parent -ne $Receipt.ParentCommitId){throw '回执父提交不符'}
 $files=@((Git $C @('diff-tree','--no-commit-id','--name-only','-r','HEAD')) -split '\r?\n'|Where-Object{$_});if(@(Compare-Object @($Receipt.Files|Sort-Object) @($files|Sort-Object)).Count){throw '提交文件集合与回执不符'}
 foreach($o in $Receipt.Objects){$tree=Git $C @('ls-tree','HEAD','--',$o.Path);if($tree -notmatch ('^100(?:644|755) blob '+[regex]::Escape($o.ObjectId)+'\t')){throw '提交对象与审核快照不符'}}
}
function Invoke-StudyPublish([pscustomobject]$Config,[pscustomobject]$Snapshot,[switch]$DryRun){
 $lock=$null;$id=$null;$files=@()
 try{
  Assert-Repository $Config
  if(@(Test-PublishSnapshot $Snapshot).Count){throw '审核后来源变化'}
  $remote=Get-RemoteHead $Config;$parent=Git $Config @('rev-parse','HEAD');if(-not $remote -or $parent -ne $remote){throw '本地与远端 main 不一致；落后/领先/分叉停止'}
    $changed=@();foreach($e in $Snapshot.Entries){$dirty=Git $Config @('status','--porcelain','--',$e.DestinationPath);$different=(Get-FileFingerprint $e.AbsoluteDestination) -ne $e.ReviewedSha256;if($different -or $dirty){if($dirty -and $e.SourcePath -ne $e.AbsoluteDestination){throw "目标已有未发布更改，需先核对差异: $($e.DestinationPath)"};$changed+=$e}}
  if(-not $changed.Count){
   foreach($e in $Snapshot.Entries){$status=Git $Config @('status','--porcelain','--',$e.DestinationPath);if($status){throw '目标文件与HEAD仍有未提交变化，不能当作已发布'}}
   return New-Result 'NoChange' $null @() @()
  }
  foreach($e in $changed){$r=Invoke-GitChecked $Config.RepositoryRoot @('check-ignore','--',$e.DestinationPath) $Config.NetworkTimeoutSeconds;if($r.ExitCode -eq 0){throw "目标被忽略: $($e.DestinationPath)"};if($r.ExitCode -gt 1){throw '忽略规则核查失败'};if($e.SourcePath -ne $e.AbsoluteDestination -and (Git $Config @('status','--porcelain','--',$e.DestinationPath))){throw "目标已有未发布更改，需先核对差异: $($e.DestinationPath)"}}
  foreach($e in $changed){$tracked=Git $Config @('ls-files','--',$e.DestinationPath);$e|Add-Member -NotePropertyName ChangeKind -NotePropertyValue $(if($tracked){'修改'}else{'新增'}) -Force}
  $snapshotChanged=[pscustomobject]@{Entries=$changed;Subjects=$Snapshot.Subjects}
  $logs=Get-PublishLogPlan $Config $snapshotChanged;$files=@($changed.DestinationPath)+@($logs.RepositoryFiles)
  foreach($p in $logs.RepositoryFiles){if(Git $Config @('status','--porcelain','--',$p)){throw "日志已有未发布变化: $p"}}
  if($DryRun){$r=New-Result 'DryRun' $null $files @();$r|Add-Member -NotePropertyName LogFiles -NotePropertyValue @($logs.Files.Path);$r|Add-Member -NotePropertyName ExternalLinkCheck -NotePropertyValue $Snapshot.ExternalLinkCheck;return $r}
  $lock=Enter-PublishLock $Config;Assert-Repository $Config
  if((Git $Config @('rev-parse','HEAD')) -ne $parent -or (Get-RemoteHead $Config) -ne $remote -or @(Test-PublishSnapshot $Snapshot).Count){throw '并发修改导致前置检查失效'}
  $before=@{};foreach($e in $changed){$before[$e.DestinationPath]=Get-FileFingerprint $e.AbsoluteDestination}
  foreach($e in $changed){Write-VerifiedBytes $e.AbsoluteDestination $e.Bytes $before[$e.DestinationPath]}
  Write-PublishLogPlan $logs|Out-Null
  if(@(Test-PublishSnapshot $Snapshot).Count){throw '写入期间审核来源变化'}
  Assert-Repository $Config
  $objects=@();foreach($p in $files){$path=Join-Path $Config.RepositoryRoot $p;$oid=Git $Config @('hash-object','--no-filters','--',$path);$objects+=[pscustomobject]@{Path=$p;ObjectId=$oid;Sha256=(Get-FileFingerprint $path)}}
  $null=Git $Config (@('-c','core.autocrlf=false','add','--')+$files)
  $indexed=@((Git $Config @('diff','--cached','--name-only')) -split '\r?\n'|Where-Object{$_});if(@(Compare-Object @($files|Sort-Object) @($indexed|Sort-Object)).Count){throw '暂存集合与清单不符，未提交'}
  foreach($o in $objects){if((Get-IndexRecord $Config $o.Path) -ne $o.ObjectId -or (Get-FileFingerprint (Join-Path $Config.RepositoryRoot $o.Path)) -ne $o.Sha256){throw '暂存摘要不匹配；过滤器/并发变化停止'}}
  if((Git $Config @('rev-parse','HEAD')) -ne $parent -or @(Test-PublishSnapshot $Snapshot).Count){throw '提交前HEAD/审核来源变化'}
  $null=Git $Config @('commit','-m',('notes: 更新 '+($Snapshot.Subjects -join '、')));$id=Git $Config @('rev-parse','HEAD')
  $receipt=[pscustomobject]@{SchemaVersion=1;CommitId=$id;ParentCommitId=$parent;RemoteUrl=$Config.ExpectedRemote;Files=$files;Objects=$objects;Status='CommittedNotPushed'}
  Assert-ExactCommit $Config $receipt;Write-Receipt $Config $receipt
  Push-AndConfirm $Config $receipt
 }catch{if($id){New-Result 'CommittedNotPushed' $id $files @($_.Exception.Message)}else{New-Result 'Blocked' $null $files @($_.Exception.Message)}}finally{if($lock){$lock.Dispose()}}
}
function Retry-StudyPush([pscustomobject]$Config,[pscustomobject]$Receipt){
 $lock=$null
 try{Assert-Repository $Config;$lock=Enter-PublishLock $Config;$saved=Get-Content -LiteralPath (Join-Path $Config.RepositoryRoot '.publish-state/last-publish.json') -Raw|ConvertFrom-Json
  if($Receipt.CommitId -ne $saved.CommitId -or $Receipt.RemoteUrl -ne $Config.ExpectedRemote -or $saved.RemoteUrl -ne $Config.ExpectedRemote){throw '仅允许本机已记录回执重试'};Assert-ExactCommit $Config $saved
  if(Confirm-RemoteCommit $Config $saved.CommitId){return New-Result 'Pushed' $saved.CommitId $saved.Files @()}
  $head=Get-RemoteHead $Config;if($head -ne $saved.ParentCommitId){throw '远端已前进/分叉；不能自动重试'}
  Push-AndConfirm $Config $saved
 }catch{New-Result 'Blocked' $null @() @($_.Exception.Message)}finally{if($lock){$lock.Dispose()}}
}
Export-ModuleMember -Function Invoke-GitChecked,Invoke-StudyPublish,Retry-StudyPush,Assert-Repository,Get-RemoteHead,New-Result



