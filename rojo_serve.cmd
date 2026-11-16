@echo off
rem ssb (출근길 서바이벌) - Rojo server. Port 34880 (set in default.project.json).
rem Connects only to the Studio place 128125794321191 (servePlaceIds). Lune (96192775933291) is blocked.
cd /d "%~dp0"
title Rojo - ssb (CommuteSurvival) - port 34880
rojo.exe serve
pause
