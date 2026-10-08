#requires -Version 7.2
param([string]$Destination='S:\GitHub\HitszCourseNote',[string]$RemoteUrl='https://github.com/frredomerror91-netizen/HitszCourseNote.git',[string]$ToolPackagePath=(Split-Path $PSScriptRoot -Parent),[switch]$DryRun,[switch]$Execute,[switch]$PublishBootstrap,[switch]$ResumeInstallation)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Bootstrap.psm1') -DisableNameChecking
try{if($RemoteUrl -ne 'https://github.com/frredomerror91-netizen/HitszCourseNote.git'){throw '初始化目标不符'};$result=Install-StudyPublisher -Destination $Destination -RemoteUrl $RemoteUrl -ToolPackagePath $ToolPackagePath -DryRun:$DryRun -Execute:$Execute -PublishBootstrap:$PublishBootstrap -ResumeInstallation:$ResumeInstallation; $result|ConvertTo-Json -Depth 8;if($result.Status -in @('Blocked','Unknown','CommittedNotPushed')){exit 1}}catch{[pscustomobject]@{Status='Blocked';Errors=@($_.Exception.Message)}|ConvertTo-Json;exit 1}

