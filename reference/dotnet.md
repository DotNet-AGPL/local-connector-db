# 单文件 C#（SDK 档扩展）

13 个预编译工具覆盖不到的任务，可以直接写一个 `.cs` 文件，用整个 .NET/NuGet 生态完成，不需要建项目。

## 前提

- 客户机有 **.NET SDK ≥ 10 正式版**（`dotnet --list-sdks` 可查）
- 只有 runtime、或版本低于 10：不能用这条路径，回到预编译工具
- 首次还原依赖需要网络

## 最小骨架

```csharp
#:package Humanizer@2.14.1
using System.Globalization;
using Humanizer;

Console.WriteLine(TimeSpan.FromMinutes(90).Humanize(2, new CultureInfo("zh-CN")));
```

```bash
dotnet run demo.cs
```

文件顶部的 `#:` 指令会生成一个临时虚拟项目，SDK 负责还原、编译、运行。

## 常用指令

| 指令 | 作用 |
|---|---|
| `#:package 包名@版本` | 引用 NuGet 包；必须写版本 |
| `#:sdk Microsoft.NET.Sdk.Web` | 换 SDK（默认 `Microsoft.NET.Sdk`） |
| `#:property 名=值` | 设置 MSBuild 属性，如 `TargetFramework`、`PublishAot`、`RuntimeIdentifier` |
| `#:include helpers.cs` | 编译同目录源码；`shared/**/*.cs` 支持通配（会禁用构建缓存） |
| `#:project ../Lib/Lib.csproj` | 引用现有项目，也可用 `dotnet reference add --file demo.cs ../Lib/Lib.csproj` |

## 运行与发布

```bash
dotnet run demo.cs                 # 运行（有 .csproj 的目录里要用 --file）
dotnet run --file demo.cs -- 参数   # 明确指定入口并传参
dotnet publish demo.cs -o ./out    # 默认 NativeAOT，产物不依赖运行时
dotnet clean demo.cs               # 清理该脚本的生成产物
```

需要固定 AOT 目标：

```csharp
#:property PublishAot=true
#:property RuntimeIdentifier=linux-x64   // win-x64 / osx-arm64 同样可用
```

## 没有 Visual Studio C++ 也能 AOT

加一行包引用即可复用 [PublishAotCross.Tools](https://github.com/DotNet-AGPL/PublishAotCross.Tools)：

```csharp
#:package PublishAotCross.Tools@1.0.3.14
#:property PublishAot=true
#:property RuntimeIdentifier=win-x64
Console.WriteLine("hello");
```

实测（Windows 11 + SDK 11.0.100，无 VS C++）：

| 目标 | 产物 | 说明 |
|---|---|---|
| win-x64 | 1.07 MB | 冷启动约 70 ms |
| linux-x64 | 1.30 MB | 在 WSL 实跑通过 |

该包是 `netstandard2.0`、不锁 ILCompiler，SDK 10 及以上普遍可用；新 SDK 若改了原生发布目标而失效，退回 `dotnet run` 即可。

## 分发

```bash
dotnet publish demo.cs -o ./dist     # 直接发给同事（单文件，无需运行时）
dotnet pack demo.cs                  # 生成 .nupkg，用 dotnet tool install 安装
dotnet project convert demo.cs       # 需要长期维护时转成正式项目
```

## 坑

- 目录里有 `.csproj` 时，`dotnet run demo.cs` 会把文件名当应用参数，必须用 `--file`
- AOT 下反射、`Reflection.Emit`、动态代理会失败：写 `#:property PublishAot=false`，或确认库本身支持 AOT
- 包版本必须显式固定，避免构建漂移
- 只从官方源还原；离线机器要提前预热 NuGet 缓存
- 脚本是一次性的，没有测试与版本管理；稳定后应转成正式项目

## 装 SDK（附录）

`dotnet --list-sdks` 里没有 ≥ 10 的正式版时，先问用户是否安装，确认后执行：

```bash
# Windows
winget install Microsoft.DotNet.SDK.11

# macOS
brew install --cask dotnet-sdk

# Linux（Ubuntu 示例）
sudo apt install dotnet-sdk-11.0
```

装完用 `dotnet --list-sdks` 确认。只用正式版，不用 preview/RC。无管理员或没有包管理器时，用官方脚本装到用户目录：

```bash
curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
bash /tmp/dotnet-install.sh --channel 11.0 --install-dir "$HOME/.dotnet"
"$HOME/.dotnet/dotnet" --list-sdks
```

装 SDK 只对这条 SDK 档有用；只使用预编译工具时不需要安装。
