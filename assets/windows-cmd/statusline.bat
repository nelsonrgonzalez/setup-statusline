@echo off
:: Claude Code statusline launcher — CMD (Windows) version.
:: This batch file is a thin wrapper that delegates to statusline.ps1.
:: Both files must be placed in the same directory (e.g. %USERPROFILE%\.claude\).
::
:: Prerequisites: PowerShell 5.1+ (pre-installed on Windows 10+).
:: ANSI colors require Windows Terminal, VS Code terminal, or Windows 10 v1511+.
::
:: Prefers PowerShell 7 (pwsh) when available; falls back to Windows PowerShell 5.1.
where pwsh >nul 2>&1 && (
    pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0statusline.ps1"
) || (
    powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0statusline.ps1"
)
