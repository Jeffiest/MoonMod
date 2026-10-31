# Draws the Gauntlet's seven shortcut-door keys (32x32 each), each in the colour its door is lit with
# (src/moonmod/dungeonmap_layout.cpp DngShortcutDoorTint): Bone, Moustache, Shipcabin, Stone, Handle, Pitchdark, Silver.
param([string]$OutDir, [string]$Preview)
Add-Type -AssemblyName System.Drawing
$keys = @(
  @{ stem = 'key_bone';      rgb = @(255, 240, 170) },
  @{ stem = 'key_moustache'; rgb = @(255, 140, 40) },
  @{ stem = 'key_shipcabin'; rgb = @(40, 200, 215) },
  @{ stem = 'key_stone';     rgb = @(150, 165, 200) },
  @{ stem = 'key_handle';    rgb = @(255, 210, 40) },
  @{ stem = 'key_pitchdark'; rgb = @(160, 60, 230) },
  @{ stem = 'key_silver';    rgb = @(215, 230, 255) }
)
function Shade([int[]]$rgb, [double]$f) {
  $c = foreach ($v in $rgb) { [int][Math]::Max(0, [Math]::Min(255, $v * $f)) }
  [System.Drawing.Color]::FromArgb(255, $c[0], $c[1], $c[2])
}
function DrawKey([int[]]$rgb) {
  $s = 128
  $big = New-Object System.Drawing.Bitmap $s, $s, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($big)
  $g.SmoothingMode = 'AntiAlias'
  $outline = [System.Drawing.Color]::FromArgb(255, 28, 18, 12)
  # the key's body as one path: bow (ring), shaft running down-right, two teeth
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $path.AddEllipse(10, 10, 52, 52)
  $shaft = New-Object System.Drawing.Drawing2D.GraphicsPath
  $shaft.AddPolygon([System.Drawing.PointF[]]@(
    [System.Drawing.PointF]::new(48, 56), [System.Drawing.PointF]::new(56, 48),
    [System.Drawing.PointF]::new(118, 110), [System.Drawing.PointF]::new(110, 118)))
  $teeth = New-Object System.Drawing.Drawing2D.GraphicsPath
  $teeth.AddPolygon([System.Drawing.PointF[]]@(
    [System.Drawing.PointF]::new(92, 100), [System.Drawing.PointF]::new(100, 92),
    [System.Drawing.PointF]::new(112, 80), [System.Drawing.PointF]::new(104, 72), [System.Drawing.PointF]::new(84, 92)))
  $teeth.AddPolygon([System.Drawing.PointF[]]@(
    [System.Drawing.PointF]::new(76, 84), [System.Drawing.PointF]::new(84, 76),
    [System.Drawing.PointF]::new(94, 66), [System.Drawing.PointF]::new(86, 58), [System.Drawing.PointF]::new(68, 76)))
  $region = New-Object System.Drawing.Region $path
  $region.Union($shaft); $region.Union($teeth)
  # outline: the body drawn a little larger in the dark colour
  $pen = New-Object System.Drawing.Pen $outline, 9
  $pen.LineJoin = 'Round'
  foreach ($p in @($path, $shaft, $teeth)) { $g.DrawPath($pen, $p) }
  # fill: light top-left to dark bottom-right
  $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush ([System.Drawing.Point]::new(0, 0)), ([System.Drawing.Point]::new($s, $s)), (Shade $rgb 1.15), (Shade $rgb 0.55)
  $g.FillRegion($brush, $region)
  # the bow's hole, and its rim
  $g.CompositingMode = 'SourceCopy'
  $g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(0, 0, 0, 0))), 26, 26, 20, 20)
  $g.CompositingMode = 'SourceOver'
  $g.DrawEllipse((New-Object System.Drawing.Pen $outline, 6), 26, 26, 20, 20)
  # a glint on the bow
  $g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(220, 255, 255, 255))), 18, 17, 10, 7)
  $small = New-Object System.Drawing.Bitmap 32, 32, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $gs = [System.Drawing.Graphics]::FromImage($small)
  $gs.InterpolationMode = 'HighQualityBicubic'
  $gs.DrawImage($big, 0, 0, 32, 32)
  return $small
}
New-Item -ItemType Directory -Force $OutDir | Out-Null
$sheet = New-Object System.Drawing.Bitmap (7 * 96), 96
$gsheet = [System.Drawing.Graphics]::FromImage($sheet)
$gsheet.Clear([System.Drawing.Color]::FromArgb(255, 40, 34, 30))
$gsheet.InterpolationMode = 'NearestNeighbor'
for ($i = 0; $i -lt $keys.Count; $i++) {
  $icon = DrawKey $keys[$i].rgb
  $icon.Save((Join-Path $OutDir ($keys[$i].stem + '.png')), [System.Drawing.Imaging.ImageFormat]::Png)
  $gsheet.DrawImage($icon, $i * 96, 0, 96, 96)
}
if ($Preview) { $sheet.Save($Preview, [System.Drawing.Imaging.ImageFormat]::Png) }
"drew $($keys.Count) keys"
