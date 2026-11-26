@echo off
rem 重新编译 tide_audio.dll（需要 MinGW64 的 gcc 在 PATH 里）
cd /d "%~dp0"
gcc -shared -O2 -static-libgcc -o ..\tide_audio.dll tide_audio.c -lwinmm -lm
if errorlevel 1 (
  echo build failed
  exit /b 1
)
echo built ..\tide_audio.dll
