# Codex Desktop 对话恢复工具

[English](README.md) | [中文](README.zh-CN.md)

这个目录放的是一套 Windows 辅助脚本，用来在通过 CC Switch 切换 API/provider 后，把本地 Codex Desktop 对话重新恢复到桌面端侧边栏里。

主入口是：

```bat
D:\codex\desktop\restore-codex-desktop-conversations.bat
```

它会读取本机 `~\.codex\sessions` 里的 Codex rollout 会话，让你选择原来的 provider，打开 CC Switch 让你手动切换 API/provider，然后修复 Codex Desktop 的本地索引和状态，让选中的对话重新显示出来。

## 它会做什么

PowerShell 脚本只修改本机 Codex Desktop 的本地状态：

- 重建 `~\.codex\session_index.jsonl`。
- 给 `~\.codex\state_5.sqlite` 里缺失的 threads 记录补行。
- 把选中的对话标记为可见、非归档。
- 把选中的对话映射到工作区，默认是 `D:\codex`。
- 默认把恢复的对话加入 Codex Desktop 的 Pinned。
- 默认在 CC Switch 切换后，把选中会话的 provider 元数据更新为当前 provider。

它不会把对话上传到 OpenAI/ChatGPT，也不会做云同步。这只是本地可见性和索引修复工具。

## 推荐流程

1. 先预览，不改任何文件：

```bat
D:\codex\desktop\restore-codex-desktop-conversations.bat -DryRun
```

2. 检查表格。表格会显示每个会话的 ID、provider、更新时间、标题和最近消息摘要。

3. 确认没问题后运行正式恢复：

```bat
D:\codex\desktop\restore-codex-desktop-conversations.bat
```

4. 选择这些旧对话原来使用的 API/provider。

5. 脚本会打开 CC Switch。你在 CC Switch 里手动切换到目标 API/provider。

6. 脚本提示时，完全退出 Codex Desktop。如果托盘里还有 Codex，也要从托盘退出。

7. 回到命令行按 Enter，等待修复完成。

8. 重新打开 Codex Desktop。恢复的对话应该会出现在 `D:\codex` 工作区下面，通常也会显示在 Pinned 里。

## 常用命令

只预览：

```bat
D:\codex\desktop\restore-codex-desktop-conversations.bat -DryRun
```

只恢复某个旧 provider 的会话：

```bat
D:\codex\desktop\restore-codex-desktop-conversations.bat -Provider yuan
```

恢复所有 provider 的本地会话：

```bat
D:\codex\desktop\restore-codex-desktop-conversations.bat -AllProviders
```

指定 CC Switch 路径：

```bat
D:\codex\desktop\restore-codex-desktop-conversations.bat -CcSwitchPath "C:\Users\asus\AppData\Local\Programs\CC Switch\cc-switch.exe"
```

不打开 CC Switch，只修复本地显示：

```bat
D:\codex\desktop\restore-codex-desktop-conversations.bat -NoCcSwitch
```

保留旧会话原来的 provider 元数据，不改成当前 provider：

```bat
D:\codex\desktop\restore-codex-desktop-conversations.bat -KeepOriginalProvider
```

恢复但不加入 Pinned：

```bat
D:\codex\desktop\restore-codex-desktop-conversations.bat -NoPin
```

指定另一个工作区：

```bat
D:\codex\desktop\restore-codex-desktop-conversations.bat -WorkspaceRoot "D:\another-workspace"
```

## 参数说明

- `-DryRun`：只显示将要恢复哪些会话，不修改任何文件。
- `-Provider <名称>`：只恢复原 `model_provider` 等于该名称的会话。
- `-AllProviders`：恢复所有本地 rollout 会话。
- `-NoCcSwitch`：不打开 CC Switch。
- `-NoPrompt`：尽量使用默认值，减少交互式提示。
- `-NoWaitForCodexExit`：不等待 Codex Desktop 退出。谨慎使用，因为 Desktop 运行中可能覆盖脚本刚写入的状态。
- `-KeepOriginalProvider`：不把选中会话的 rollout 元数据改成切换后的当前 provider。
- `-NoPin`：恢复可见性，但不加入 Pinned。
- `-IncludeNonInteractive`：包含 exec/review 等非交互式 rollout 会话。
- `-SummaryChars <数字>`：控制预览表格里摘要的最大长度。

## 备份

脚本在修改重要本地文件前，会在原文件旁边创建带时间戳的备份，例如：

- `session_index.jsonl.bak_YYYYMMDD_HHMMSS`
- `state_5.sqlite.bak_YYYYMMDD_HHMMSS`
- `.codex-global-state.json.bak_YYYYMMDD_HHMMSS`
- `rollout-....jsonl.bak_YYYYMMDD_HHMMSS`

如果恢复后看起来不对，先停止使用 Codex Desktop，再手动把最近的备份恢复回去。

## 依赖

- Windows PowerShell。
- 本机存在 Codex Desktop 数据目录 `~\.codex`。
- 如果需要自动打开 CC Switch，则需要已经安装 CC Switch。
- `sqlite3` 在 `PATH` 中可用，因为脚本需要修复 `state_5.sqlite`。

这台机器上通常检测到的 CC Switch 路径是：

```text
C:\Users\asus\AppData\Local\Programs\CC Switch\cc-switch.exe
```

## 注意事项

脚本以本地 rollout 文件为数据源。它使用的是 Codex 对话/session ID，不使用 subagent ID。

如果修复后某个对话仍然没有出现，先运行：

```bat
D:\codex\desktop\restore-codex-desktop-conversations.bat -DryRun
```

确认这个对话在列表中，然后完全退出 Codex Desktop，再重新运行正式恢复。不要在 Desktop 仍运行时强行修复，除非你明确知道自己在做什么。
