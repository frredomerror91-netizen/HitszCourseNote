# 学习笔记自动发布工具

## 用途和边界

本工具把“已审核的本次笔记”精确提交并正常推送到 HitszCourseNote 的 main。它不是全盘同步软件，不批量迁移旧笔记，不使用强制推送，不传播源文件删除，不收集教材或私密资料。

需要 PowerShell 7.2 或更高版本、Git 和本机 Git 凭据。内容审核仍由生成任务完成；结构和秘密扫描只是启发式检查，不能保证事实正确、版权合规或完全没有敏感信息。该仓库是公开仓库，上传前必须检查发布范围和题源公开权限。

## 一次性准备

1. 在自己的 PowerShell 完成浏览器登录；不把密码、Token 或设备代码发送给助手。

```powershell
git credential-manager github login --username frredomerror91-netizen --browser
```

2. 初始化工具包。第一次先试运行；目标已经安装时仅使用后述续接命令，不覆盖目录。

```powershell
pwsh -NoProfile -File .\scripts\Initialize-Publisher.ps1 -DryRun
pwsh -NoProfile -File .\scripts\Initialize-Publisher.ps1 -Execute
```

3. 查看初始化结果以及作者身份（该邮箱可能公开到提交记录），确认安装回执和远端无误后上传初始工具：

```powershell
git -C S:\GitHub\HitszCourseNote config user.name
git -C S:\GitHub\HitszCourseNote config user.email
pwsh -NoProfile -File S:\GitHub\HitszCourseNote\scripts\Initialize-Publisher.ps1 -Destination S:\GitHub\HitszCourseNote -Execute -ResumeInstallation -PublishBootstrap
```

安装会从固定空仓库 clone，复制固定工具清单，并创建被忽略的 publisher.local.json。真实上传只能正常推送；拒绝权限或 main 规则时，不绕过限制。续接仅对本机安装回执对应的工具使用。回执缺失或工具变化时停止，不重新覆盖。

本地配置中的 SourceRoots 明确哪些来源目录可被读取，AllowedSubjects 明确哪些学科可写入。不要把整个磁盘或整个混合工作区设为来源。配置示例只启用部分已有学科，增补学科需要明确检查。配置、清单和回执都不会上传。

## 日常使用：不需要自己写 JSON

在生成笔记的任务中说明“完成内容审核后，发布本次笔记到 HitszCourseNote 的某学科目录”。接入仓库规则的助手负责建立清单并执行以下流程，而不是让你手动敲 Git 命令。

示例：外部来源的一份已审核章节型笔记。示例路径需替换成实际文件，不用于第一次迁移旧笔记。

```powershell
$repo = 'S:\GitHub\HitszCourseNote'
$cfg = Join-Path $repo 'publisher.local.json'
$request = Join-Path $repo ('.publish-state\review-' + [guid]::NewGuid().ToString('N') + '.json')
pwsh -NoProfile -File "$repo\scripts\New-PublishRequest.ps1" -ConfigPath $cfg -Notes 'S:\agent\概率论\本次新笔记.md' -Subject '概率论' -Kind chapter-note -ReviewCompleted -RequestPath $request
pwsh -NoProfile -File "$repo\scripts\Publish-StudyNotes.ps1" -ConfigPath $cfg -RequestPath $request -DryRun
# 确认试运行范围与内容审核后执行：
pwsh -NoProfile -File "$repo\scripts\Publish-StudyNotes.ps1" -ConfigPath $cfg -RequestPath $request
```

一般专题笔记、指南可使用 general-note；不得为绕过章节型检查将完整章节故意标成 general-note。Markdown 文档应遵循学习笔记 Skill 的适用规则，流程索引或 README 不机械配题。

直接在专用 clone 中生成也可发布，只会提交明确审核的本次文件。来自其他目录的笔记复制到目标时，若目标已有未提交修改，则停止核对差异，不覆盖。章节型检查当前针对已约定的“本章路线 / 学习单元 / 本章小结 / 本章练习与检验”模板，其他课程模板请先调整校验器而不是静默跳过。

本地图片根据内联 Markdown 引用收集到清单，审核记录覆盖笔记和图片的摘要。链接中的空格建议用 URL 编码或尖括号。参考式链接、HTML 图片暂不支持，会报错；引用 PDF 需改成经确认可公开的来源链接，首版不自动上传教材。引用其他本地笔记时，要一起显式列入本次清单。

外链默认不联网检查，结果明确标为 NotRun。可在发布入口添加 -CheckExternalLinks 进行有限 HEAD 检查，网络或站点拒绝显示 Unverified，不声称链接一定失效，也不把 HEAD 可达当作内容可信证明。

## 日志

工具核对本次变化后更新最近的来源 CHANGELOG、仓库 CHANGELOG、本地每日总日志和当日总结。相同日期合并，同一内容版本不重复。外部总日志不被收集到公开仓库。

先完成发布工具日志再执行 Git，若日志写入失败，停止提交并列出已经写入的路径。工具无法跨多个项目文件原子更新；冲突时不静默覆盖。源项目日志也可能有其他编辑，脚本会比较写入前摘要。

## 结果与恢复

- DryRun：展示拟发布文件与日志路径，不写入目标、日志或提交。
- NoChange：本次文件已经与已同步版本一致，没有新提交。
- Blocked：前置条件或校验失败；成果保留。若已经暂存，检查 index，不用硬重置。
- CommittedNotPushed：本地提交存在，但未证实上传。看 CommitId 和本地回执。
- Pushed：已查询远端确认目标提交；回执落盘失败时会附警告。
- Unknown：网络结果不明，不能说已上传或未上传。

正常发布因网络、权限或竞态失败后，只能重试本机已记录的提交，不重复提交：

```powershell
pwsh -NoProfile -File S:\GitHub\HitszCourseNote\scripts\Publish-StudyNotes.ps1 -ConfigPath S:\GitHub\HitszCourseNote\publisher.local.json -RetryReceiptPath S:\GitHub\HitszCourseNote\.publish-state\last-publish.json
```

若 HEAD 不再是回执提交，远端前进/分叉，或者出现其他暂存内容，自动恢复停止。初始化失败用 Initialize-Publisher 的续接入口，不用普通笔记回执重试。不要在此时 force push 或随手把旧历史一起上传。

## 验证和限制

测试不依赖 Pester，使用独立临时 Git 仓库与裸远端，不触碰真实笔记。测试目录位于当前目录的 work/publisher-tests，保留用于排查。

```powershell
pwsh -NoProfile -File .\tests\Test-StudyPublisher.ps1 -Suite All
```

首版不含 GitHub Actions、定时任务、网页聊天导出或旧笔记迁移。普通 ChatGPT 网页中的文字不会自动变成本地文件；需要保存到已接入的工作区。只有在当前生成任务主动调用发布入口或专用仓库规则适用时，流程才运行；不存在隐藏的后台监听服务。

锁保护本工具的并发调用，摘要和暂存检查降低外部编辑风险，但其他程序若在最小检查窗口同时修改 Git 数据，不能作事务隔离保证。发生异常应核对差异，不擅自清理。Git hooks/过滤器影响结果时停止；不绕过用户已有规则。

