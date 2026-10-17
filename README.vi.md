# SweepLab

[English](README.md) | **Tiếng Việt**

**Quét trước, xóa sau.** SweepLab là một module PowerShell kèm công cụ dòng lệnh, chuyên tìm phần dung lượng có thể thu hồi trên Windows - file tạm, crash dump, cache, log cũ - và cả build output của project như `node_modules`, `target/`, `.venv`; chỉ xóa đúng những gì nó đã báo cáo.

Một lần audit trên máy dev thật đã lấy lại **52,2 GB** mà không đụng tới tài liệu, mã nguồn hay ứng dụng đang chạy.

## Vì sao có repo này

Dọn ổ Windows bằng tay nghĩa là đo từng thư mục, đoán xem cache nào an toàn, và tự nhớ danh sách đường dẫn "đừng đụng vào". SweepLab gom phần đó thành quy trình lặp lại được và kiểm tra được:

- mọi lệnh quét chỉ đọc, và in ra chính xác nó tìm thấy bao nhiêu byte;
- mọi thao tác xóa đều phải bật thủ công, có xác nhận, và báo cáo lại những gì không xóa được thay vì cố phá;
- các vùng nguy hiểm - `WinSxS`, MSI cache, page file - nằm ngoài phạm vi theo thiết kế, ghi rõ trong [docs/safety.md](docs/safety.md).

## Yêu cầu

- Windows 10 hoặc 11
- Windows PowerShell 5.1 hoặc PowerShell 7+
- Không cần quyền admin cho các nhóm mặc định. Vài target cần admin được đánh dấu `RequiresAdmin` và báo là thất bại/bỏ qua, không tự nâng quyền.

## Cài đặt

```powershell
# Dùng trực tiếp từ bản clone
Import-Module ./src/SweepLab/SweepLab.psd1

# Hoặc copy module vào module path của user
Copy-Item -Recurse ./src/SweepLab "$HOME/Documents/WindowsPowerShell/Modules/SweepLab"
Import-Module SweepLab
```

## Dùng nhanh

```powershell
# 1. Xem SweepLab biết dọn những gì, target nào cần admin
./scripts/sweeplab.ps1 targets

# 2. Quét toàn bộ và in ra các mục lớn nhất (chỉ đọc)
./scripts/sweeplab.ps1 scan

# 3. Xóa đúng những gì vừa quét, vẫn giữ ngưỡng tuổi 24 giờ
./scripts/sweeplab.ps1 clean -Delete

# 4. Build output trong một cây project: xem trước rồi xóa
./scripts/sweeplab.ps1 build -Path C:\Dev\MyApp
./scripts/sweeplab.ps1 build-clean -Path C:\Dev\MyApp -Delete

# 5. Báo cáo dung lượng, sau đó xuất file để lưu lại
./scripts/sweeplab.ps1 report -Path C:\ -Top 25
./scripts/sweeplab.ps1 export -OutputDirectory ./data/reports/local
```

Làm y hệt bằng module, kết quả là object có kiểu nên pipe được:

```powershell
Get-SweepJunk -Category user-temp -MinAgeHours 24 | Format-Table Category, Length, Path
Get-SweepJunk | Remove-SweepJunk -PruneEmptyDirectories -WhatIf

Get-SweepBuildArtifact -RootPath C:\Dev | Select-Object -First 20
Get-SweepBuildArtifact -RootPath C:\Dev -IncludeRustTarget | Remove-SweepBuildArtifact -WhatIf

Get-SweepSpaceReport -Path C:\ -TopFiles 25 -GroupDepth 2
Get-SweepJunk | Export-SweepReport -OutputDirectory ./data/reports/local
```

## Danh sách lệnh

| Lệnh | Việc nó làm |
|---|---|
| `Get-SweepTarget` | Liệt kê target dựng sẵn kèm nhóm, đường dẫn đã resolve và có cần admin không. |
| `Get-SweepJunk` | Quét các target rác và phát ra mỗi file một object `SweepLab.JunkItem`. |
| `Remove-SweepJunk` | Xóa các `JunkItem`; hỗ trợ `-WhatIf`, `-Confirm`, `-PruneEmptyDirectories`. |
| `Get-SweepBuildArtifact` | Tìm thư mục dependency/build (`node_modules`, `target`, `.venv`, ...) trong cây project. |
| `Remove-SweepBuildArtifact` | Xóa các thư mục đó; hỗ trợ `-WhatIf` và `-Confirm`. |
| `Get-SweepSpaceReport` | Quét một gốc và báo tổng dung lượng, file lớn nhất, nhóm thư mục lớn nhất, thư mục không đọc được. |
| `Export-SweepReport` | Ghi bản tóm tắt Markdown kèm CSV chi tiết từ mọi kết quả quét. |

Lệnh CLI: `targets`, `scan`, `clean`, `build`, `build-clean`, `report`, `export`, `help`. `scan`, `build`, `report` chỉ đọc; `clean` và `build-clean` từ chối chạy nếu thiếu `-Delete`, để một lần gõ nhầm không thể xóa gì.

## Nhóm rác hệ thống

| Nhóm | Target mặc định |
|---|---|
| `user-temp` | `%TEMP%` |
| `windows-temp` | `%SystemRoot%\Temp` |
| `crash-dumps` | `%LOCALAPPDATA%\CrashDumps`, `%SystemRoot%\Minidump`, `%SystemRoot%\LiveKernelReports` |
| `app-cache` | `INetCache`, cache shader DirectX, WER report archive và queue |
| `package-cache` | cache pip, npm, Yarn, NuGet v3 |
| `dev-cache` | cache trình duyệt Playwright/Puppeteer, cache Gradle |
| `old-logs` | `%SystemRoot%\Logs\CBS` |
| `custom` | Bất cứ thư mục nào bạn truyền qua `-Path` |

`-Path` **thêm** thư mục vào lần quét, không thay thế target dựng sẵn. Nếu chỉ muốn quét đúng những thư mục bạn truyền vào, ghép `-Category custom` với `-Path` - `Get-SweepJunk -Category custom -Path D:\scratch` sẽ không chạm tới target dựng sẵn nào. Danh mục đầy đủ ở [docs/targets.md](docs/targets.md), cam kết an toàn ở [docs/safety.md](docs/safety.md).

## Build artifact

Các tên thư mục rõ nghĩa được khớp mặc định: `node_modules`, `__pycache__`, `.pytest_cache`, `.mypy_cache`, `.ruff_cache`, `.tox`, `.venv`, `.next`, `.turbo`, `.parcel-cache`, `.svelte-kit`, `.nuxt`, `.output`, `.angular`, `.dart_tool`, `coverage`, `.nyc_output`, `bower_components`.

Các tên mơ hồ - `bin`, `obj`, `build`, `dist`, `target` - không bao giờ được khớp ngầm. Bật thủ công bằng `-Name bin,obj`, và dùng `-IncludeRustTarget` cho `target`, chỉ khớp khi có `Cargo.toml` nằm cạnh chứng minh đó là target của Cargo.

## Object đầu ra

Mọi lệnh đều phát ra object có kiểu, nên kết quả pipe được thay vì phải cắt chuỗi: `SweepLab.TargetDefinition`, `SweepLab.JunkItem`, `SweepLab.BuildArtifact`, `SweepLab.SpaceReport`, `SweepLab.RemovalSummary` (và `SweepLab.FileItem` cho bản ghi file trung gian).

Hai lệnh xóa trả về mỗi target root một bản tóm tắt:

| Trường | Ý nghĩa |
|---|---|
| `DeletedCount`, `DeletedBytes`, `DeletedSize` | Đã xóa trong nhóm này |
| `PrunedDirectoryCount` | Thư mục bị xóa vì đã rỗng (`-PruneEmptyDirectories`) |
| `MissingCount` | Đã biến mất trước đó - do root khác hoặc công cụ khác xóa |
| `FailedCount`, `FailedBytes`, `FailedSize` | Giữ lại vì đang bị khóa hoặc được bảo vệ |

Thao tác xóa không dừng ở lỗi đầu tiên: file bị khóa được đếm và báo lại, phần còn lại vẫn chạy tiếp.

## Cam kết an toàn

1. Quét và xóa là hai lệnh tách biệt. `Get-Sweep*` chỉ đọc, và luôn nói rõ sẽ giải phóng bao nhiêu byte.
2. Xóa phải bật ở cả hai tầng: `-WhatIf`/`-Confirm` trong module (`ConfirmImpact = 'High'`, nên mặc định có hỏi) và `-Delete` ở CLI.
3. File mới hơn `-MinAgeHours` (mặc định 24 giờ) không bao giờ bị đụng, nhờ đó download đang chạy, log đang ghi và build cache đang dùng vẫn nguyên.
4. Blocklist mặc định từ chối đường dẫn của harness agent đang chạy và database SQLite đang mở, từ chối gốc ổ đĩa, đoạn `.`/`..` và reparse point. Người gọi chỉ thêm được pattern, không xóa được mặc định.
5. `-PruneEmptyDirectories` chỉ xóa thư mục đã rỗng sau khi xóa file.
6. Thứ SweepLab không xóa được thì báo lại, không lách: quyền admin, `WinSxS`, MSI cache và page file vẫn là thao tác thủ công.

## Ngoài phạm vi

`C:\Windows\WinSxS` (chỉ DISM), `C:\Windows\Installer` (MSI cache - dùng công cụ chuyên dụng kiểu InstallerClean), `C:\Windows\Assembly`, `C:\Windows\Prefetch`, `hiberfil.sys` (`powercfg /h off`), `pagefile.sys`, `swapfile.sys`. Chi tiết trong [docs/safety.md](docs/safety.md).

## Phát triển

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
Invoke-Pester -Path ./tests
Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

`./scripts/ci/Invoke-SweepLabTests.ps1` chạy đúng bộ test mà CI dùng và báo lỗi nếu thiếu bản Pester phù hợp. CI chạy script này một lần trên PowerShell 7 và một lần trên Windows PowerShell 5.1.

Xem [CONTRIBUTING.md](CONTRIBUTING.md). File trong module là ASCII thuần và pass PSScriptAnalyzer với 0 cảnh báo theo cấu hình đã commit, trên cả Windows PowerShell 5.1 lẫn PowerShell 7.

## Cấu trúc repo

```
src/SweepLab/           module: Private/ là helper, Public/ là lệnh, manifest
scripts/sweeplab.ps1    lớp dòng lệnh
scripts/ci/             điểm vào cho CI (script chạy test)
tests/                  bộ test Pester
docs/                   danh mục target và cam kết an toàn
data/reports/local/     báo cáo sinh ra (git bỏ qua)
```

## Giấy phép

MIT - xem [LICENSE](LICENSE).
