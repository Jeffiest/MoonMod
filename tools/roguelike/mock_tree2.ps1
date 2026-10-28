# Mockups of the Norune Eternal tree in two looks, from the game's own art and font.
Add-Type -AssemblyName System.Drawing
$shots = 'E:\Gauntlet-build\run\shots'
$out = 'C:\Users\armor\AppData\Local\Temp\claude\E--Moonmod\89c2a8fa-0420-4f51-80fe-67f3c0677cb6\scratchpad'
$fonts = New-Object System.Drawing.Text.PrivateFontCollection
$fonts.AddFontFile('E:\Gauntlet-build\Chronicle\port\build\windows-x64-release\lang\font.ttf')
$family = $fonts.Families[0]
function F($px) { New-Object System.Drawing.Font($family, $px, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel) }
function B($a, $r, $g, $b) { New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($a, $r, $g, $b)) }
function P($a, $r, $g, $b, $w) { New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb($a, $r, $g, $b)), $w }
function Crop($bmp, $x, $y, $w, $h) { $bmp.Clone((New-Object System.Drawing.Rectangle $x, $y, $w, $h), [System.Drawing.Imaging.PixelFormat]::Format32bppArgb) }

$pack = [System.Drawing.Bitmap]::FromFile("$shots\itempack.png")
$shop = [System.Drawing.Bitmap]::FromFile("$shots\g5shop.png")
$hud = [System.Drawing.Bitmap]::FromFile("$shots\clean_cursed.png")
$title = [System.Drawing.Bitmap]::FromFile("$shots\g2t.png")
$icon = @{
  sword   = Crop $pack 252 700 66 62
  shield  = Crop $pack 6 370 130 130
  crystal = Crop $pack 6 640 112 120
  map     = Crop $pack 134 642 120 112
  heart   = Crop $pack 256 640 64 58
  drop    = Crop $pack 4 286 60 64
  pouch   = Crop $pack 398 534 70 70
  curse   = Crop $pack 780 630 240 124
  poison  = Crop $pack 780 482 240 124
  freeze  = Crop $pack 780 340 240 124
  stamina = Crop $pack 534 482 240 124
  goo     = Crop $pack 534 630 240 124
  box     = Crop $pack 148 370 138 130
  chest   = [System.Drawing.Bitmap]::FromFile('E:\Moonmod\mods\moonmod.roguelike\resources\hud\cache.png')
}
$heading = Crop $shop 425 100 430 70        # "NORUNE ETERNAL" in the game's heading lettering
$hand = Crop $shop 332 430 66 54            # the pointing hand
for ($yy = 0; $yy -lt $hand.Height; $yy++) { for ($xx = 0; $xx -lt $hand.Width; $xx++) {
  $px = $hand.GetPixel($xx, $yy)
  if ($px.B -gt $px.R + 6 -and $px.R -lt 190) { $hand.SetPixel($xx, $yy, [System.Drawing.Color]::FromArgb(0, 0, 0, 0)) }
} }
$corner = Crop $hud 582 42 82 82            # the yellow selection corners of the quick slots
$plate = Crop $shop 124 84 1034 648         # the stone plate

function Draw-Plate($g, $x, $y, $w, $h) {
  # The stone plate from clean parts only: corners, edge strips clear of the page's text, and a clean patch tiled.
  $c = 40; $pw = $plate.Width; $ph = $plate.Height
  function Piece($sx, $sy, $sw, $sh, $dx, $dy, $dw, $dh) {
    $g.DrawImage($plate, (New-Object System.Drawing.Rectangle $dx, $dy, $dw, $dh),
      (New-Object System.Drawing.Rectangle $sx, $sy, $sw, $sh), [System.Drawing.GraphicsUnit]::Pixel)
  }
  $px = 44; $py = 384; $pw2 = 104; $ph2 = 210 # a clean patch of stone
  for ($ty = $y + $c; $ty -lt $y + $h - $c; $ty += $ph2) {
    for ($tx = $x + $c; $tx -lt $x + $w - $c; $tx += $pw2) {
      $dw = [Math]::Min($pw2, $x + $w - $c - $tx); $dh = [Math]::Min($ph2, $y + $h - $c - $ty)
      Piece $px $py $dw $dh $tx $ty $dw $dh
    }
  }
  Piece $c 0 200 $c ($x + $c) $y ($w - 2 * $c) $c                       # top
  Piece $c ($ph - $c) 200 $c ($x + $c) ($y + $h - $c) ($w - 2 * $c) $c   # bottom
  Piece 0 $c $c 300 $x ($y + $c) $c ($h - 2 * $c)                        # left
  Piece ($pw - $c) $c $c 300 ($x + $w - $c) ($y + $c) $c ($h - 2 * $c)   # right
  Piece 0 0 $c $c $x $y $c $c
  Piece ($pw - $c) 0 $c $c ($x + $w - $c) $y $c $c
  Piece 0 ($ph - $c) $c $c $x ($y + $h - $c) $c $c
  Piece ($pw - $c) ($ph - $c) $c $c ($x + $w - $c) ($y + $h - $c) $c $c
}
function Text($g, $s, $x, $y, $px, $brush, [switch]$center) {
  $f = F $px
  if ($center) { $x -= $g.MeasureString($s, $f).Width / 2 }
  $g.DrawString($s, $f, (B 210 8 8 12), $x + 2, $y + 2)
  $g.DrawString($s, $f, $brush, $x, $y)
}
function New-Canvas() {
  $bmp = New-Object System.Drawing.Bitmap 1280, 960
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
  # the title's backdrop, blurred by scaling down and up, and darkened into a night sky
  $small = New-Object System.Drawing.Bitmap 80, 60
  $gs = [System.Drawing.Graphics]::FromImage($small)
  $gs.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
  $gs.DrawImage($title, 0, 0, 80, 60); $gs.Dispose()
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.DrawImage($small, -20, -20, 1320, 1000)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
  $g.FillRectangle((B 175 6 8 26), 0, 0, 1280, 960)
  $rand = New-Object System.Random 7
  for ($i = 0; $i -lt 170; $i++) {
    $s = $rand.Next(1, 4); $a = $rand.Next(90, 255)
    $g.FillEllipse((B $a 230 232 255), $rand.Next(0, 1280), $rand.Next(0, 960), $s, $s)
  }
  return @($bmp, $g)
}
$gold = B 255 248 206 92; $white = B 255 240 238 232; $grey = B 255 150 150 160; $crimson = B 255 236 92 118

# ---------------------------------------------------------------- Look A2: the sky, zoomed on Arms, readable
function Label($g, $s, $x, $y, $px, $brush) {
  # a label on a dark plate, centred on x
  $f = F $px
  $sz = $g.MeasureString($s, $f)
  $w = $sz.Width + 14; $h = $sz.Height + 2
  $rect = New-Object System.Drawing.RectangleF ($x - $w / 2), $y, $w, $h
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $rad = 9
  $path.AddArc($rect.X, $rect.Y, 2 * $rad, 2 * $rad, 180, 90); $path.AddArc($rect.Right - 2 * $rad, $rect.Y, 2 * $rad, 2 * $rad, 270, 90)
  $path.AddArc($rect.Right - 2 * $rad, $rect.Bottom - 2 * $rad, 2 * $rad, 2 * $rad, 0, 90); $path.AddArc($rect.X, $rect.Bottom - 2 * $rad, 2 * $rad, 2 * $rad, 90, 90)
  $path.CloseFigure()
  $g.FillPath((B 200 10 10 22), $path)
  $g.DrawPath((P 90 200 200 230 1), $path)
  Text $g $s ($x - $sz.Width / 2) ($y + 1) $px $brush
}
function Node($g, $x, $y, $state, $iconName, $col, [switch]$key, [switch]$sel) {
  $r = $(if ($key) { 40 } else { 31 })
  if ($state -eq 'own') {
    for ($h = 3; $h -ge 1; $h--) { $g.FillEllipse((B (34 * $h) $col[0] $col[1] $col[2]), $x - $r - 6 * $h, $y - $r - 6 * $h, 2 * ($r + 6 * $h), 2 * ($r + 6 * $h)) }
    $ring = P 255 $col[0] $col[1] $col[2] 5
  } elseif ($state -eq 'open') { $ring = P 255 214 214 228 4 } else { $ring = P 170 90 90 104 3 }
  if ($key) {
    # a crown of eight points around a Keystone
    for ($i = 0; $i -lt 8; $i++) {
      $a = $i * [Math]::PI / 4; $tip = $r + 14
      $pts = [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF ($x + [Math]::Cos($a - 0.18) * ($r - 2)), ($y + [Math]::Sin($a - 0.18) * ($r - 2))),
        (New-Object System.Drawing.PointF ($x + [Math]::Cos($a) * $tip), ($y + [Math]::Sin($a) * $tip)),
        (New-Object System.Drawing.PointF ($x + [Math]::Cos($a + 0.18) * ($r - 2)), ($y + [Math]::Sin($a + 0.18) * ($r - 2))))
      $g.FillPolygon($(if ($state -eq 'lock') { B 160 80 76 60 } else { B 255 248 206 92 }), $pts)
    }
  }
  $g.FillEllipse((B 255 24 22 36), $x - $r, $y - $r, 2 * $r, 2 * $r)
  $g.DrawEllipse($ring, $x - $r, $y - $r, 2 * $r, 2 * $r)
  $bs = $(if ($key) { 52 } else { 42 })
  $attr = New-Object System.Drawing.Imaging.ImageAttributes
  $m = New-Object System.Drawing.Imaging.ColorMatrix; $m.Matrix33 = $(if ($state -eq 'lock') { 0.4 } else { 1.0 }); $attr.SetColorMatrix($m)
  $g.DrawImage($icon.box, (New-Object System.Drawing.Rectangle ($x - $bs / 2), ($y - $bs / 2), $bs, $bs), 0, 0, $icon.box.Width, $icon.box.Height, [System.Drawing.GraphicsUnit]::Pixel, $attr)
  $ic = $icon[$iconName]; $badge = $ic.Width -gt 150
  $iw = $(if ($badge) { $bs - 8 } else { $bs - 14 }); $ih = $(if ($badge) { ($bs - 8) / 2 } else { $bs - 14 })
  $g.DrawImage($ic, (New-Object System.Drawing.Rectangle ($x - $iw / 2), ($y - $ih / 2), $iw, $ih), 0, 0, $ic.Width, $ic.Height, [System.Drawing.GraphicsUnit]::Pixel, $attr)
  if ($sel) {
    foreach ($q in @(@(0, 0), @(1, 0), @(0, 1), @(1, 1))) {
      $g.DrawImage($corner, (New-Object System.Drawing.Rectangle ($x - $bs / 2 - 8 + $q[0] * ($bs - 12)), ($y - $bs / 2 - 8 + $q[1] * ($bs - 12)), 28, 28), (New-Object System.Drawing.Rectangle ($q[0] * 56), ($q[1] * 56), 26, 26), [System.Drawing.GraphicsUnit]::Pixel)
    }
    $g.DrawImage($hand, [int]($x - $r - 76), [int]($y - 27), 66, 54)
  }
}

$bmp, $g = New-Canvas
$edge = @(248, 206, 92); $endu = @(150, 214, 255); $craft = @(196, 160, 255)
# the neighbouring constellations, glowing at the edges of the view
foreach ($nb in @(@('Fortune', 1250, 470, @(196, 160, 255)), @('Spirit', 30, 470, @(255, 170, 120)), @('Norune Eternal', 640, 960, @(255, 240, 190)))) {
  for ($h = 6; $h -ge 1; $h--) { $g.FillEllipse((B (10 * $h) $nb[3][0] $nb[3][1] $nb[3][2]), $nb[1] - 30 * $h, $nb[2] - 30 * $h, 60 * $h, 60 * $h) }
}
Text $g "Fortune  >" 1120 452 24 (B 255 196 160 255)
Text $g "<  Spirit" 22 452 24 (B 255 255 170 120)
# links: trunk, fork, paths, and the bridge to Fortune
$W = @(640, 700)
$edgeP = @(@(470, 616), @(404, 530), @(356, 442), @(326, 352)); $edgeK = @(306, 252)
$enduP = @(@(640, 594), @(640, 504), @(640, 414), @(640, 324)); $enduK = @(640, 220)
$craftP = @(@(810, 616), @(876, 530), @(924, 442), @(954, 352)); $craftK = @(974, 252)
$bridge = @(1086, 556)
$g.DrawLine((P 230 255 240 190 4), 640, 960, $W[0], $W[1])
function Chain($pts, $key, $col, $lit) {
  $px = $W[0]; $py = $W[1]; $i = 0
  foreach ($p in $pts + , $key) {
    $on = $i -lt $lit
    $g.DrawLine((P $(if ($on) { 235 } else { 90 }) $col[0] $col[1] $col[2] $(if ($on) { 4 } else { 3 })), $px, $py, $p[0], $p[1])
    $px = $p[0]; $py = $p[1]; $i++
  }
}
Chain $edgeP $edgeK $edge 3
Chain $enduP $enduK $endu 1
Chain $craftP $craftK $craft 2
$g.DrawLine((P 170 196 160 255 3), $craftP[1][0], $craftP[1][1], $bridge[0], $bridge[1])
$g.DrawLine((P 120 196 160 255 3), $bridge[0], $bridge[1], 1280, 470)
# path names
Text $g "EDGE" 170 610 30 (B 255 248 206 92)
Text $g "ENDURANCE" 562 128 30 (B 255 150 214 255)
Text $g "CRAFT" 1010 640 30 (B 255 196 160 255)
# nodes
Node $g $W[0] $W[1] 'own' 'sword' $edge
Label $g "Whetstone  3/3" $W[0] ($W[1] + 36) 19 $white
$en = @(@('Keen Edge  3/3', 'sword', 'own'), @("Smith's Start  2/3", 'sword', 'own'), @('Charged Fury', 'sword', 'own'), @('Moon Strike  0/2', 'crystal', 'open'))
$un = @(@("Gaffer's Oil  2/2", 'drop', 'own'), @('Field Repair', 'pouch', 'open'), @('Tempered Grip', 'shield', 'lock'), @('Auto-Repair Charm', 'pouch', 'lock'))
$cr = @(@("Macho's Forge  3/3", 'shield', 'own'), @('Gem Pouch', 'crystal', 'own'), @('Socket Sense', 'map', 'open'), @('Synth Mastery  0/2', 'crystal', 'lock'))
for ($i = 0; $i -lt 4; $i++) {
  Node $g $edgeP[$i][0] $edgeP[$i][1] $en[$i][2] $en[$i][1] $edge -sel:($i -eq 3)
  Label $g $en[$i][0] ($edgeP[$i][0] - 6) ($edgeP[$i][1] + 36) 18 $(if ($en[$i][2] -eq 'lock') { $grey } else { $white })
  Node $g $enduP[$i][0] $enduP[$i][1] $un[$i][2] $un[$i][1] $endu
  Label $g $un[$i][0] ($enduP[$i][0] + 0) ($enduP[$i][1] + 36) 18 $(if ($un[$i][2] -eq 'lock') { $grey } else { $white })
  Node $g $craftP[$i][0] $craftP[$i][1] $cr[$i][2] $cr[$i][1] $craft
  Label $g $cr[$i][0] ($craftP[$i][0] + 6) ($craftP[$i][1] + 36) 18 $(if ($cr[$i][2] -eq 'lock') { $grey } else { $white })
}
Node $g $edgeK[0] $edgeK[1] 'lock' 'sword' $edge -key
Label $g "Moonblade" $edgeK[0] ($edgeK[1] + 52) 20 $gold
Node $g $enduK[0] $enduK[1] 'lock' 'shield' $endu -key
Label $g "Unbreakable Bond" $enduK[0] ($enduK[1] + 52) 20 $gold
Node $g $craftK[0] $craftK[1] 'lock' 'chest' $craft -key
Label $g "Master's Gift" $craftK[0] ($craftK[1] + 52) 20 $gold
Node $g $bridge[0] $bridge[1] 'open' 'crystal' $craft
Label $g "Heirloom Vault" $bridge[0] ($bridge[1] + 36) 18 $white
# top bar: heading, star map, purses
Draw-Plate $g 396 6 488 92
$g.DrawImage($heading, 425, 16, 430, 70)
Draw-Plate $g 14 10 230 150
$g.FillRectangle((B 230 8 10 26), 30, 26, 198, 118)
$rand = New-Object System.Random 3
foreach ($cst in @(@(129, 85, 255, 240, 190), @(80, 50, 248, 206, 92), @(129, 42, 150, 214, 255), @(180, 52, 196, 160, 255), @(70, 112, 140, 226, 160), @(186, 112, 255, 170, 120), @(129, 128, 236, 92, 118))) {
  for ($i = 0; $i -lt 5; $i++) { $g.FillEllipse((B 255 $cst[2] $cst[3] $cst[4]), $cst[0] + $rand.Next(-14, 14), $cst[1] + $rand.Next(-9, 9), 4, 4) }
}
$g.DrawRectangle((P 255 248 206 92 2), 58, 34, 46, 34)
Text $g "Arms" 64 70 15 $gold
Text $g "Moon Shards 486" 900 16 22 $white
Text $g "Genie Sigils 7    Ruby Marks 4" 900 42 19 (B 255 255 214 150)
Text $g "Heat 7 x1.7    Keystones 1/2" 900 66 19 $crimson
# the detail plate
Draw-Plate $g 150 760 980 190
Text $g "Moon Strike   0/2" 190 778 32 $gold
Text $g "Edge path" 640 788 22 (B 255 248 206 92)
Text $g "5% of hits deal double damage. Rank 2: 10%." 190 822 23 $white
Text $g "Needs: Charged Fury       Opens: Moonblade (Keystone)" 190 856 21 (B 255 200 214 240)
Text $g "Next: 15 Moon Shards" 880 786 22 $white
Text $g "Cross: buy     Square: switch on/off     L1/R1: rank     R2: star map" 190 896 20 $grey
$g.Dispose(); $bmp.Save("$out\tree_sky.png", [System.Drawing.Imaging.ImageFormat]::Png); "wrote tree_sky.png"

