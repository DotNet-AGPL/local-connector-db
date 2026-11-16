# 重新构建制品

## 目录

- 全量重建与校验（rebuild.bat / rebuild.sh）
- 单库构建（build.ps1）
- RID 与全球化策略
- 产物说明

## 全量重建与校验

`bin/` 被误删时，在 skill 根目录执行：

```bash
rebuild.bat          # Windows，双击或命令行
bash rebuild.sh      # Linux / macOS
```

会重建全部制品并校验每个目录都有可执行文件（Linux 还要有 ICU）。加 `win` / `linux` 只重建单个 RID，加 `verify` 只校验不构建。

构建需要 .NET SDK 11 + PowerShell 7（`pwsh`），首次构建需联网；`verify` 模式只用 shell。

## 单库构建

源码在 `src/`，每个库一个项目：

```bash
.\build.ps1 -Only <sqlite|mysql|postgres|duckdb|clickhouse|redis|dm|mongo|sqlserver|oracle> [-Rid win-x64|linux-x64] [-Clean]
```

`-Rid` 决定产物目录（`bin/<db>-<rid>/`），跨平台编译由 PublishAotCross 完成，不需要对应的操作系统。

## RID 与全球化策略

- `Directory.Build.props` 默认 `InvariantGlobalization=true`（不需要 ICU）
- 只有 `Connector.SqlServer.csproj` 覆盖为 `false`（SqlClient 不支持不变模式），并在 linux RID 条件引用 `Icu4C.Runtime`；Windows 走系统 NLS
- restore 按 RID 走，**切换 RID 时务必带 `-Clean`**
- `Icu4C.Runtime` 77.1.5 起按目标 RID 注入 `-Wl,-rpath,$ORIGIN`，Windows 上交叉编译 linux 也能拿到正确的 `RUNPATH`，项目里不再需要 rpath 补丁。升级该包前请确认交叉编译产物仍带 `RUNPATH=$ORIGIN`（`LD_DEBUG=libs` 里能看到 `search path=/app ... (RUNPATH ...)`）

## 产物说明

产物落到 `bin/<db>-<rid>/`，目录内 `BUILD-INFO.txt` 记录 SDK 版本、构建时间与各文件 SHA256。
