# 重新构建制品

## 目录

- 按宿主重建（推荐）
- 指定目标 RID
- 只校验
- 单库构建
- RID 与全球化策略
- macOS 注意事项
- 产物说明

## 按宿主重建

`bin/` 被误删时，在仓库根目录执行：

```bash
bash rebuild.sh      # Linux→linux-x64，macOS(Apple Silicon)→osx-arm64，Git Bash→win-x64
rebuild.bat          # Windows→win-x64（双击或命令行）
```

无参数时按宿主平台自动选择 RID。Intel Mac、Linux arm64 会直接报「暂无制品」并退出，不会生成跑不起来的产物。

构建需要 .NET SDK 11 + PowerShell 7（`pwsh`），首次构建需联网；`verify` 模式只用 shell。

## 指定目标 RID

```bash
bash rebuild.sh win        # 只重建 win-x64
bash rebuild.sh linux      # 只重建 linux-x64
bash rebuild.sh osx        # 只重建 osx-arm64
bash rebuild.sh all        # 三平台
rebuild.bat linux          # 在 Windows 上交叉编译 linux-x64
rebuild.bat all            # 三平台
```

跨平台编译由 PublishAotCross 完成，不需要目标平台的操作系统；首次构建 `osx-arm64` 会额外下载 `MacOSX.SDK` 包（体积较大，需要联网）。

## 只校验

```bash
bash rebuild.sh verify         # 只校验宿主平台
bash rebuild.sh verify all     # 只校验三平台
rebuild.bat verify             # 只校验 win-x64
rebuild.bat verify all         # 只校验三平台
```

校验规则按平台分流：

- 每个 `bin/<db>-<rid>/` 必须存在 `db-<db>` 可执行文件
- 非 Windows 平台额外检查执行位（`chmod +x`）
- `sqlserver-linux-x64` 必须带 app-local ICU（`*icu*`）
- `sqlserver-osx-arm64` 用 macOS 系统 ICU，不需要 app-local 文件

## 单库构建

源码在 `src/`，每个库一个项目：

```bash
.\build.ps1 -Only <sqlite|mysql|postgres|duckdb|clickhouse|redis|dm|mongo|sqlserver|oracle>
.\build.ps1 -Only mysql -Rid linux-x64 -Clean
.\build.ps1 -Only sqlite -Rid osx-arm64
.\build.ps1 -Skip sqlserver,dm        # 跳过指定库
```

`-Rid` 省略时按宿主平台推断；值域仅 `win-x64` / `linux-x64` / `osx-arm64`，拼错会直接报错而不是生成垃圾目录。

## RID 与全球化策略

- `-Rid` 决定产物目录（`bin/<db>-<rid>/`）
- `Directory.Build.props` 默认 `InvariantGlobalization=true`（不需要 ICU）
- 只有 `Connector.SqlServer.csproj` 覆盖为 `false`（SqlClient 不支持不变模式）：linux RID 条件引用 `Icu4C.Runtime`，Windows 走系统 NLS，macOS 用系统 ICU
- restore 按 RID 走，**切换 RID 时务必带 `-Clean`**
- `Icu4C.Runtime` 77.1.5 起按目标 RID 注入 `-Wl,-rpath,$ORIGIN`，Windows 上交叉编译 linux 也能拿到正确的 `RUNPATH`，项目里不再需要 rpath 补丁。升级该包前请确认交叉编译产物仍带 `RUNPATH=$ORIGIN`（`LD_DEBUG=libs` 里能看到 `search path=/app ... (RUNPATH ...)`）

## macOS 注意事项

- `osx-arm64` 制品尚未在真机实测，目前只验证过从 Windows 交叉构建成功
- 从别的机器拷贝/下载的产物会带 quarantine 标记，首次运行前执行：
  `xattr -dr com.apple.quarantine bin/<db>-osx-arm64`
- 不需要安装 Xcode：`MacOSX.SDK` 由 PublishAotCross 自动引入，仅提供链接所需的 SDK 子集
- `sqlserver` 在非 Windows 平台走 managed SNI（`Microsoft.Data.SqlClient.SNI.runtime` 只带 Windows 原生库），`dm` 的 `DM.DmProvider` 为纯托管实现，两者都不依赖 macOS 原生库

## 产物说明

产物落到 `bin/<db>-<rid>/`，目录内 `BUILD-INFO.txt` 记录 SDK 版本、构建时间与各文件 SHA256。
