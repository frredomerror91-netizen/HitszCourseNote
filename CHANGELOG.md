# 更新日志

## 2026-10-08

### 新增

- 新增审核清单生成、笔记与路径校验、必要图片归档、成果日志、精确提交/正常推送和失败提交恢复工具，涉及 `scripts/Validation.psm1`、`scripts/PublishLogs.psm1`、`scripts/GitPublish.psm1`、`scripts/New-PublishRequest.ps1`、`scripts/Publish-StudyNotes.ps1`。
- 新增空仓库安装/初始化入口及安全续接，涉及 `scripts/Bootstrap.psm1`、`scripts/Initialize-Publisher.ps1`。
- 新增无额外依赖的隔离回归测试、使用说明、仓库生成任务规则、示例配置和忽略规则，涉及 `tests/Test-StudyPublisher.ps1`、`README.md`、`AGENTS.md`、`publisher.example.json`、`.gitignore`。

首版只处理本次审核清单；不含旧笔记迁移、全盘监听、定时任务或 GitHub Actions。本文记录工具文件成果，不表示所有来源项目已经接入或旧笔记已经上传。

### 修改

- 将原学科目录生成学习笔记后的默认发布规则写入工作区与仓库说明：只发布本次审核的 Markdown 笔记和正文引用的必要图片，拒绝 PDF、其他资料、草稿、备份及未引用附件；新增对应回归测试。涉及 `AGENTS.md`、`README.md`、`scripts/New-PublishRequest.ps1`、`tests/Test-StudyPublisher.ps1`。
