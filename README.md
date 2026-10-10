# SpeakerKeepAlive

Windows 托盘小工具:每隔几分钟发出一声很轻的提示音,防止音箱因为长时间没有信号而自动休眠/关机。

- 纯 PowerShell,无需安装依赖
- 托盘图标(右下角):右键菜单可暂停/恢复、立即试响、打开设置;双击图标直接打开设置
- 设置项:间隔(秒)、频率(Hz)、音量(满幅百分比)、时长(毫秒),保存在 `%APPDATA%\SpeakerKeepAlive\config.json`
- 登录自启(计划任务,无需管理员权限)

默认值:每 240 秒、500 Hz、1.5% 音量、400 ms。

## 安装 / 卸载

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1     # 注册登录自启并立即启动
powershell -ExecutionPolicy Bypass -File uninstall.ps1   # 卸载
```

## 调试

```powershell
powershell -ExecutionPolicy Bypass -File keepalive.ps1 -Once   # 按当前配置响一次后退出
```

## 说明

- 如果音箱仍然会关,说明提示音太轻、低于音箱的检测阈值:在设置里调大音量或提高频率。
- 实际响度同时取决于 Windows 系统音量。
- 脚本含中文,文件需保存为带 BOM 的 UTF-8(Windows PowerShell 5.1 才能正确读取)。
