@echo off
cd /d %~dp0
dcc32 -B -U"..\..\Sources\Core;..\..\Sources\Entity;..\..\Sources\Specifications" EntityDemo.dpr
