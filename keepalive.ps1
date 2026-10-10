param(
    [switch]$Once   # 只按当前配置响一次然后退出(测试用)
)

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$CfgDir = Join-Path $env:APPDATA 'SpeakerKeepAlive'
$CfgPath = Join-Path $CfgDir 'config.json'
$Defaults = @{ IntervalSeconds = 240; FreqHz = 500; VolumePercent = 1.5; DurationMs = 400 }

function Get-Config {
    $cfg = $Defaults.Clone()
    if (Test-Path $CfgPath) {
        try {
            $saved = Get-Content $CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($k in @($Defaults.Keys)) {
                if ($null -ne $saved.$k) { $cfg[$k] = [double]$saved.$k }
            }
        } catch { }   # 配置损坏则回退默认值
    }
    $cfg
}

function Save-Config($cfg) {
    New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null
    $cfg | ConvertTo-Json | Set-Content -Path $CfgPath -Encoding UTF8
}

function New-TonePlayer($cfg) {
    $rate = 44100
    $n = [int]($rate * $cfg.DurationMs / 1000)
    $fade = [Math]::Min([int]($rate * 0.15), [int]($n / 2))
    $amp = $cfg.VolumePercent / 100.0
    $ms = New-Object System.IO.MemoryStream
    $w = New-Object System.IO.BinaryWriter($ms)
    $w.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $w.Write([int](36 + $n * 2))
    $w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt ')); $w.Write([int]16)
    $w.Write([int16]1); $w.Write([int16]1); $w.Write([int]$rate)
    $w.Write([int]($rate * 2)); $w.Write([int16]2); $w.Write([int16]16)
    $w.Write([Text.Encoding]::ASCII.GetBytes('data')); $w.Write([int]($n * 2))
    for ($i = 0; $i -lt $n; $i++) {
        $env = [Math]::Min(1.0, [Math]::Min($i, $n - 1 - $i) / [Math]::Max(1, $fade))
        $s = [Math]::Sin(2 * [Math]::PI * $cfg.FreqHz * $i / $rate) * $amp * $env
        $w.Write([int16]($s * 32767))
    }
    $w.Flush(); $ms.Position = 0
    $p = New-Object System.Media.SoundPlayer($ms)
    $p.Load()
    $p
}

function New-TrayIcon([bool]$active) {
    $bmp = New-Object System.Drawing.Bitmap(32, 32)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $color = if ($active) { [System.Drawing.Color]::FromArgb(46, 160, 90) } else { [System.Drawing.Color]::Gray }
    $brush = New-Object System.Drawing.SolidBrush($color)
    $pen = New-Object System.Drawing.Pen($color, 3)
    $g.FillRectangle($brush, 3, 11, 7, 10)
    $g.FillPolygon($brush, @(
        (New-Object System.Drawing.Point(10, 11)), (New-Object System.Drawing.Point(19, 4)),
        (New-Object System.Drawing.Point(19, 28)), (New-Object System.Drawing.Point(10, 21))))
    $g.DrawArc($pen, 14, 9, 10, 14, -60, 120)
    $g.DrawArc($pen, 12, 4, 18, 24, -60, 120)
    $g.Dispose()
    $icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
    $icon
}

$script:cfg = Get-Config

if ($Once) {
    (New-TonePlayer $script:cfg).PlaySync()
    exit 0
}

# 单实例
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Global\SpeakerKeepAliveTray', [ref]$created)
if (-not $created) { exit 0 }

$script:player = New-TonePlayer $script:cfg
$script:paused = $false
$script:settingsForm = $null
$iconOn = New-TrayIcon $true
$iconOff = New-TrayIcon $false

$tray = New-Object System.Windows.Forms.NotifyIcon
$timer = New-Object System.Windows.Forms.Timer

function Update-Tray {
    $min = [Math]::Round($script:cfg.IntervalSeconds / 60.0, 1)
    $state = if ($script:paused) { '已暂停' } else { "每 $min 分钟响一次" }
    $tray.Text = "音箱保活 - $state"
    $tray.Icon = if ($script:paused) { $iconOff } else { $iconOn }
    $miPause.Text = if ($script:paused) { '恢复' } else { '暂停' }
}

function Invoke-Play { try { $script:player.Play() } catch { } }

function Apply-Config($newCfg) {
    $script:cfg = $newCfg
    Save-Config $newCfg
    $old = $script:player
    $script:player = New-TonePlayer $newCfg
    if ($old) { $old.Dispose() }
    $timer.Interval = [int]($newCfg.IntervalSeconds * 1000)
    Update-Tray
}

function Add-Row($form, $label, $y, $min, $max, $value, $decimals, $step) {
    $lb = New-Object System.Windows.Forms.Label
    $lb.Text = $label; $lb.Left = 16; $lb.Top = $y + 3; $lb.Width = 150
    $nud = New-Object System.Windows.Forms.NumericUpDown
    $nud.Left = 175; $nud.Top = $y; $nud.Width = 90
    $nud.DecimalPlaces = $decimals; $nud.Increment = $step
    $nud.Minimum = $min; $nud.Maximum = $max
    $nud.Value = [Math]::Min($max, [Math]::Max($min, [decimal]$value))
    $form.Controls.AddRange(@($lb, $nud))
    $nud
}

function Show-Settings {
    if ($script:settingsForm -and -not $script:settingsForm.IsDisposed) {
        $script:settingsForm.Activate(); return
    }
    $f = New-Object System.Windows.Forms.Form
    $f.Text = '音箱保活 - 设置'
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false
    $f.StartPosition = 'CenterScreen'; $f.ClientSize = New-Object System.Drawing.Size(290, 230)
    $f.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
    $f.TopMost = $true

    $nInterval = Add-Row $f '间隔(秒)' 16 10 3600 $script:cfg.IntervalSeconds 0 10
    $nFreq = Add-Row $f '频率(Hz)' 52 40 4000 $script:cfg.FreqHz 0 10
    $nVol = Add-Row $f '音量(%)' 88 0.1 50 $script:cfg.VolumePercent 1 0.5
    $nDur = Add-Row $f '时长(毫秒)' 124 100 3000 $script:cfg.DurationMs 0 50

    $tip = New-Object System.Windows.Forms.Label
    $tip.Text = '音量是满幅的百分比,实际响度还取决于系统音量。'
    $tip.Left = 16; $tip.Top = 158; $tip.Width = 260; $tip.Height = 34
    $tip.ForeColor = [System.Drawing.Color]::Gray

    $read = {
        @{ IntervalSeconds = [double]$nInterval.Value; FreqHz = [double]$nFreq.Value
           VolumePercent = [double]$nVol.Value; DurationMs = [double]$nDur.Value }
    }.GetNewClosure()
    $bTest = New-Object System.Windows.Forms.Button
    $bTest.Text = '试听'; $bTest.Left = 16; $bTest.Top = 194; $bTest.Width = 70
    $bTest.Add_Click({ $p = New-TonePlayer (& $read); $p.Play() }.GetNewClosure())
    $bSave = New-Object System.Windows.Forms.Button
    $bSave.Text = '保存'; $bSave.Left = 126; $bSave.Top = 194; $bSave.Width = 70
    $bSave.Add_Click({ Apply-Config (& $read); $f.Close() }.GetNewClosure())
    $bCancel = New-Object System.Windows.Forms.Button
    $bCancel.Text = '取消'; $bCancel.Left = 202; $bCancel.Top = 194; $bCancel.Width = 70
    $bCancel.Add_Click({ $f.Close() }.GetNewClosure())

    $f.Controls.AddRange(@($tip, $bTest, $bSave, $bCancel))
    $script:settingsForm = $f
    $f.Show()
}

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miSettings = $menu.Items.Add('设置...')
$miTest = $menu.Items.Add('立即响一次')
$miPause = $menu.Items.Add('暂停')
$menu.Items.Add('-') | Out-Null
$miExit = $menu.Items.Add('退出')

$miSettings.Add_Click({ Show-Settings })
$miTest.Add_Click({ Invoke-Play })
$miPause.Add_Click({ $script:paused = -not $script:paused; Update-Tray })
$miExit.Add_Click({
    $timer.Stop(); $tray.Visible = $false; $tray.Dispose()
    [System.Windows.Forms.Application]::ExitThread()
})
$tray.ContextMenuStrip = $menu
$tray.Add_DoubleClick({ Show-Settings })

$timer.Interval = [int]($script:cfg.IntervalSeconds * 1000)
$timer.Add_Tick({ if (-not $script:paused) { Invoke-Play } })

Update-Tray
$tray.Visible = $true
$timer.Start()
Invoke-Play
[System.Windows.Forms.Application]::Run()
