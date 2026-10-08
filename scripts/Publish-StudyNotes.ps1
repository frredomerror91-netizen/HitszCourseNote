#requires -Version 7.2
[CmdletBinding(DefaultParameterSetName='Publish')]
param([Parameter(Mandatory)][string]$ConfigPath,[Parameter(Mandatory,ParameterSetName='Publish')][string]$RequestPath,[Parameter(ParameterSetName='Publish')][switch]$DryRun,[Parameter(ParameterSetName='Publish')][switch]$CheckExternalLinks,[Parameter(Mandatory,ParameterSetName='Retry')][string]$RetryReceiptPath)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Validation.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'GitPublish.psm1') -DisableNameChecking
try{
 $config=Read-PublisherConfig $ConfigPath
 $state=Join-Path $config.RepositoryRoot '.publish-state'
 if($PSCmdlet.ParameterSetName -eq 'Retry'){
  $p=[IO.Path]::GetFullPath($RetryReceiptPath);if($p -ne [IO.Path]::GetFullPath((Join-Path $state 'last-publish.json'))){throw '只允许本机固定路径恢复回执'};Assert-NoReparse $p;$result=Retry-StudyPush $config (Get-Content -LiteralPath $p -Raw|ConvertFrom-Json)
 }else{
  $p=[IO.Path]::GetFullPath($RequestPath);if(-not(Test-Inside $p $state)){throw '清单必须位于本仓库状态目录'};Assert-NoReparse $p;$snapshot=Get-PublishSnapshot $config (Get-Content -LiteralPath $p -Raw|ConvertFrom-Json)
  $linkResults=@();if($CheckExternalLinks){foreach($url in @($snapshot.ExternalLinks|Select-Object -First 20)){try{$res=Invoke-WebRequest -Uri $url -Method Head -TimeoutSec 10 -MaximumRedirection 5;$linkResults+=[pscustomobject]@{Url=$url;Status=[string]$res.StatusCode}}catch{$linkResults+=[pscustomobject]@{Url=$url;Status='Unverified';Reason=$_.Exception.Message}}};$snapshot.ExternalLinkCheck='BestEffortRequested';if($snapshot.ExternalLinks.Count -gt 20){$linkResults+=[pscustomobject]@{Url='(remaining)';Status='NotRun'}}}
  $result=Invoke-StudyPublish $config $snapshot -DryRun:$DryRun;$result|Add-Member -NotePropertyName ExternalLinkCheck -NotePropertyValue $snapshot.ExternalLinkCheck -Force;$result|Add-Member -NotePropertyName ExternalLinkResults -NotePropertyValue $linkResults
 }
 $result|ConvertTo-Json -Depth 8
 if($result.Status -in @('Blocked','Unknown','CommittedNotPushed')){exit 1}
}catch{[pscustomobject]@{Status='Blocked';CommitId=$null;Errors=@($_.Exception.Message)}|ConvertTo-Json -Depth 4;exit 1}
