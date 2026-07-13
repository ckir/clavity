@echo off
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0fake-claude.ps1" %*
