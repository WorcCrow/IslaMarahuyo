# Capture-Studio.ps1
# Saves a PNG of the Roblox Studio window (or a crop of it) for an update page's screenshots.
# Studio is usually in device emulation (iPhone 6 Plus, 736x414), which puts the game view at
# roughly X 550, Y 358, W 828, H 465 inside a 1938x1048 window -- check one full capture first
# if the layout has changed.
#
#   powershell -ExecutionPolicy Bypass -File Capture-Studio.ps1 -Out <png> [-X x -Y y -W w -H h]
#
# Set the view first: in Edit mode, execute_luau `workspace.CurrentCamera.CFrame = ...`;
# in a playtest, set the Client camera to Scriptable and position it the same way.
param(
    [Parameter(Mandatory = $true)][string]$Out,
    [int]$X = -1, [int]$Y = -1, [int]$W = -1, [int]$H = -1
)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
}
"@
[Win]::SetProcessDPIAware() | Out-Null
$p = Get-Process RobloxStudioBeta | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { throw "Roblox Studio is not running" }
# not $h: PowerShell names are case-insensitive, so $h would overwrite the -H crop height
$hwnd = $p.MainWindowHandle
# A minimized window has no client area to print: restore it without taking focus
# (SW_SHOWNOACTIVATE), give the viewport time to redraw, and minimize it again afterwards.
$wasMinimized = [Win]::IsIconic($hwnd)
if ($wasMinimized) {
    [Win]::ShowWindow($hwnd, 4) | Out-Null
    Start-Sleep -Milliseconds 1500
}
$r = New-Object Win+RECT
[Win]::GetWindowRect($hwnd, [ref]$r) | Out-Null
$ww = $r.Right - $r.Left; $wh = $r.Bottom - $r.Top
$full = New-Object System.Drawing.Bitmap $ww, $wh
$g = [System.Drawing.Graphics]::FromImage($full)
$hdc = $g.GetHdc()
# PW_RENDERFULLCONTENT (2) captures GPU-drawn content even if the window is covered
[Win]::PrintWindow($hwnd, $hdc, 2) | Out-Null
$g.ReleaseHdc($hdc); $g.Dispose()
if ($wasMinimized) { [Win]::ShowWindow($hwnd, 7) | Out-Null } # SW_SHOWMINNOACTIVE

$result = $full
if ($W -gt 0 -and $H -gt 0) {
    # draw the crop into a fresh bitmap: Bitmap.Clone on a PrintWindow bitmap throws "Out of memory"
    $result = New-Object System.Drawing.Bitmap $W, $H
    $cg = [System.Drawing.Graphics]::FromImage($result)
    $cg.DrawImage($full, (New-Object System.Drawing.Rectangle 0, 0, $W, $H), (New-Object System.Drawing.Rectangle $X, $Y, $W, $H), [System.Drawing.GraphicsUnit]::Pixel)
    $cg.Dispose()
    $full.Dispose()
}
$result.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$result.Dispose()
Write-Output "saved $Out (window $ww x $wh)"
