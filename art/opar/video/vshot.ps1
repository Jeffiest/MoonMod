# vshot.ps1 NAME FRAMES SCRIPT AT [SHOT]: one headless 1280x720 run of the Opar showcase from the video save's
# snapshot (save_video_base), screenshots at the listed frames (NAME_<frame>.png). SHOT is video_shot.txt's text.
param([string]$Name, [int]$Frames, [string]$Script, [string]$At, [string]$Shot = "200 40")
$b = 'E:\Gauntlet-build\Chronicle\port\build\windows-x64-release'
$r = 'E:\Gauntlet-build\run'
$v = 'C:\Users\armor\AppData\Local\Temp\claude\E--Moonmod\4802d590-5ba4-453b-97df-ff78ca19c2de\scratchpad'
if (Test-Path "$v\save_video") { Remove-Item -Recurse -Force "$v\save_video" }
Copy-Item -Recurse "$v\save_video_base" "$v\save_video"
Set-Content -Path "$b\video_shot.txt" -Value $Shot -Encoding ascii
New-Item -ItemType Directory -Force "$r\shots\video" | Out-Null
$scriptFile = "$r\shots\video\$Name.txt"
Set-Content -Path $scriptFile -Value $Script -Encoding ascii
Set-Location $b
& .\darkcloud_video.exe --data "$r\data" --save "$v\save_video" --headless --width 1280 --height 720 --frames $Frames --input $scriptFile --screenshot "$r\shots\video\$Name.png" --screenshot-at $At *> "$r\shots\video\$Name.log"
"$Name exit $LASTEXITCODE"
