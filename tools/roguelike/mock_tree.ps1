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

# ---------------------------------------------------------------- Look A: a constellation of moons
$bmp, $g = New-Canvas
Draw-Plate $g 396 10 488 92
$g.DrawImage($heading, 425, 20, 430, 70)
Text $g "Moon Shards 194" 930 30 26 $white
Text $g "Heat 7  -  Shards x1.7" 930 64 22 $crimson
$cx = 640; $cy = 420
# branches: name, colour, title position, label side, nodes {label, icon, state, x, y}
$branches = @(
  @{ name = 'Arms'; col = @(248, 206, 92); t = @(150, 128); side = 'alt'; nodes = @(@('Whetstone', 'sword', 'own', 532, 340), @("Macho's Forge", 'shield', 'own', 440, 292), @("Smith's Start", 'sword', 'open', 345, 258), @('Heirloom Vault', 'crystal', 'lock', 245, 240), @("Master's Gift", 'sword', 'lock', 140, 236)) },
  @{ name = 'Allies'; col = @(150, 214, 255); t = @(1110, 128); side = 'alt'; nodes = @(@('Matataki Embassy', 'heart', 'own', 748, 340), @("Golden Atla's Call", 'heart', 'open', 845, 292), @('Companion', 'heart', 'lock', 945, 258), @('Stances', 'heart', 'lock', 1048, 240)) },
  @{ name = 'Provisions'; col = @(140, 226, 160); t = @(150, 668); side = 'below'; nodes = @(@('Repair Kit', 'pouch', 'own', 512, 484), @("Baker's Bundle", 'pouch', 'own', 410, 540), @('Full Waterskin', 'drop', 'open', 298, 580), @("Gaffer's Wagon", 'map', 'lock', 182, 600)) },
  @{ name = 'Fortune'; col = @(196, 160, 255); t = @(1110, 668); side = 'below'; nodes = @(@("Dran's Shrine", 'crystal', 'own', 788, 484), @('Shard Lens', 'crystal', 'own', 892, 540), @('Cache Sense', 'chest', 'open', 1002, 580), @('Moon Blessing', 'crystal', 'lock', 1116, 600)) },
  @{ name = "Dark Genie's Pacts"; col = @(236, 92, 118); t = @(450, 712); side = 'right'; nodes = @(@('Crowded Halls', 'stamina', 'on', 640, 574), @('Hardened Hide', 'poison', 'on', 640, 632), @('Sharp Claws', 'curse', 'off', 640, 690), @('Twin Wardens', 'goo', 'open', 640, 748)) }
)
$selected = $null
foreach ($br in $branches) {
  $c = $br.col
  $px = $cx; $py = $cy
  foreach ($n in $br.nodes) {
    $lit = $n[2] -eq 'own' -or $n[2] -eq 'on'
    $g.DrawLine((P ($(if ($lit) { 230 } else { 90 })) $c[0] $c[1] $c[2] 3), $px, $py, $n[3], $n[4])
    $px = $n[3]; $py = $n[4]
  }
  $k = 0
  foreach ($n in $br.nodes) {
    $k++
    $x = $n[3]; $y = $n[4]
    $state = $n[2]
    $r = $(if ($br.side -eq 'right') { 24 } else { 27 })
    if ($state -eq 'own' -or $state -eq 'on') {
      for ($h = 3; $h -ge 1; $h--) { $g.FillEllipse((B (36 * $h) $c[0] $c[1] $c[2]), $x - $r - 6 * $h, $y - $r - 6 * $h, 2 * ($r + 6 * $h), 2 * ($r + 6 * $h)) }
      $g.FillEllipse((B 255 34 30 48), $x - $r, $y - $r, 2 * $r, 2 * $r)
      $g.DrawEllipse((P 255 $c[0] $c[1] $c[2] 4), $x - $r, $y - $r, 2 * $r, 2 * $r)
    } elseif ($state -eq 'open' -or $state -eq 'off') {
      $g.FillEllipse((B 255 26 26 38), $x - $r, $y - $r, 2 * $r, 2 * $r)
      $g.DrawEllipse((P 255 200 200 214 3), $x - $r, $y - $r, 2 * $r, 2 * $r)
    } else {
      $g.FillEllipse((B 230 18 18 26), $x - $r, $y - $r, 2 * $r, 2 * $r)
      $g.DrawEllipse((P 150 96 96 110 2), $x - $r, $y - $r, 2 * $r, 2 * $r)
    }
    $ic = $icon[$n[1]]
    $badge = $ic.Width -gt 150
    $iw = $(if ($badge) { 42 } else { 34 }); $ih = $(if ($badge) { 22 } else { 34 })
    if ($state -eq 'lock') {
      $attr = New-Object System.Drawing.Imaging.ImageAttributes
      $m = New-Object System.Drawing.Imaging.ColorMatrix; $m.Matrix33 = 0.35
      $attr.SetColorMatrix($m)
      $g.DrawImage($ic, (New-Object System.Drawing.Rectangle ($x - $iw / 2), ($y - $ih / 2), $iw, $ih), 0, 0, $ic.Width, $ic.Height, [System.Drawing.GraphicsUnit]::Pixel, $attr)
    } else {
      $g.DrawImage($ic, [int]($x - $iw / 2), [int]($y - $ih / 2), $iw, $ih)
    }
    $lab = $(if ($state -eq 'lock') { $grey } else { $white })
    $name = $n[0]
    if ($state -eq 'on') { $name += '   ON' } elseif ($state -eq 'off') { $name += '   OFF' }
    $lw = $g.MeasureString($name, (F 17)).Width
    if ($br.side -eq 'right') { Text $g $name ($x + $r + 10) ($y - 11) 17 $(if ($state -eq 'on') { $crimson } else { $lab }) }
    elseif ($br.side -eq 'below' -or ($k % 2 -eq 0)) { Text $g $name ($x - $lw / 2) ($y + $r + 3) 17 $lab }
    else { Text $g $name ($x - $lw / 2) ($y - $r - 24) 17 $lab }
    if ($n[0] -eq "Smith's Start") { $selected = @($x, $y) }
  }
  Text $g $br.name $br.t[0] $br.t[1] 30 (B 255 $c[0] $c[1] $c[2]) -center
}
# the centre: Norune Eternal
for ($h = 5; $h -ge 1; $h--) { $g.FillEllipse((B (24 * $h) 255 240 190), $cx - 46 - 9 * $h, $cy - 46 - 9 * $h, 2 * (46 + 9 * $h), 2 * (46 + 9 * $h)) }
$g.FillEllipse((B 255 250 244 220), $cx - 46, $cy - 46, 92, 92)
$g.FillEllipse((B 70 190 180 150), $cx - 18, $cy - 26, 26, 22); $g.FillEllipse((B 60 190 180 150), $cx + 8, $cy + 6, 22, 18); $g.FillEllipse((B 50 190 180 150), $cx - 24, $cy + 14, 14, 12)
# the hand on the selected node
$g.DrawImage($hand, [int]($selected[0] - 98), [int]($selected[1] - 27), 66, 54)
# the detail plate
Draw-Plate $g 190 790 900 156
Text $g "Smith's Start" 236 806 34 $gold
# (rank in the text)
Text $g "Rank 0/3  -  next 5 Moon Shards" 580 812 24 $white
Text $g "The starting weapon starts one level up per rank." 236 854 24 $white
Text $g "Cross: buy     Square: switch on/off     L1/R1: rank" 236 894 21 $grey
$g.Dispose(); $bmp.Save("$out\tree_constellation.png", [System.Drawing.Imaging.ImageFormat]::Png); "wrote tree_constellation.png"

# ---------------------------------------------------------------- Look B: a build-up chart
$bmp, $g = New-Canvas
Draw-Plate $g 20 20 1240 920
$g.DrawImage($heading, 425, 34, 430, 70)
Text $g "Moon Shards 194" 70 52 24 $white
Text $g "Heat 7   x1.7" 1010 52 24 $crimson
$cols = @(
  @{ name = 'Arms'; icon = 'sword'; nodes = @(@('Whetstone', 'sword', 'own', '3/3'), @("Macho's Forge", 'shield', 'own', '1/3'), @("Smith's Start", 'sword', 'open', '0/3'), @('Heirloom Vault', 'crystal', 'lock', '0/1'), @("Master's Gift", 'sword', 'lock', '0/1')) },
  @{ name = 'Provisions'; icon = 'pouch'; nodes = @(@('Repair Kit', 'pouch', 'own', '2/2'), @("Baker's Bundle", 'pouch', 'own', '1/1'), @('Full Waterskin', 'drop', 'open', '0/2'), @("Gaffer's Wagon", 'map', 'lock', '0/2')) },
  @{ name = 'Allies'; icon = 'heart'; nodes = @(@('Matataki Embassy', 'heart', 'own', '1/1'), @("Golden Atla's Call", 'heart', 'open', '0/1'), @('Companion', 'heart', 'lock', '0/1'), @('Stances', 'heart', 'lock', '0/1')) },
  @{ name = 'Fortune'; icon = 'crystal'; nodes = @(@("Dran's Shrine", 'crystal', 'own', '2/3'), @('Shard Lens', 'crystal', 'own', '1/3'), @('Cache Sense', 'chest', 'open', '0/1'), @('Moon Blessing', 'crystal', 'lock', '0/1')) },
  @{ name = 'Pacts'; icon = 'curse'; nodes = @(@('Crowded Halls', 'stamina', 'on', '2/2'), @('Hardened Hide', 'poison', 'on', '1/3'), @('Sharp Claws', 'curse', 'off', '1/2'), @('Twin Wardens', 'goo', 'open', '0/2')) }
)
$colx = 70; $colw = 228
$c = 0
foreach ($col in $cols) {
  $x0 = $colx + $c * $colw
  $isPact = $col.name -eq 'Pacts'
  $g.FillRectangle((B 70 $(if ($isPact) { 120 } else { 20 }) 20 $(if ($isPact) { 40 } else { 50 })), $x0, 122, $colw - 16, 720)
  $ic = $icon[$col.icon]; $badge = $ic.Width -gt 150
  $g.DrawImage($ic, $x0 + 8, 132, $(if ($badge) { 58 } else { 40 }), $(if ($badge) { 30 } else { 40 }))
  Text $g $col.name ($x0 + $(if ($badge) { 70 } else { 54 })) 136 24 $(if ($isPact) { $crimson } else { $gold })
  $k = 0
  foreach ($n in $col.nodes) {
    $bx = $x0 + 66; $by = 190 + $k * 118
    if ($k -gt 0) { $g.DrawLine((P 220 $(if ($n[2] -eq 'lock') { 110 } else { 230 }) $(if ($n[2] -eq 'lock') { 110 } else { 200 }) $(if ($n[2] -eq 'lock') { 120 } else { 120 }) 5), $bx + 40, $by - 52, $bx + 40, $by) }
    $g.DrawImage($icon.box, $bx, $by, 80, 76)
    $ni = $icon[$n[1]]; $nb = $ni.Width -gt 150
    $iw = $(if ($nb) { 62 } else { 46 }); $ih = $(if ($nb) { 32 } else { 46 })
    if ($n[2] -eq 'lock') {
      $attr = New-Object System.Drawing.Imaging.ImageAttributes
      $m = New-Object System.Drawing.Imaging.ColorMatrix; $m.Matrix33 = 0.3; $attr.SetColorMatrix($m)
      $g.DrawImage($ni, (New-Object System.Drawing.Rectangle ($bx + 40 - $iw / 2), ($by + 38 - $ih / 2), $iw, $ih), 0, 0, $ni.Width, $ni.Height, [System.Drawing.GraphicsUnit]::Pixel, $attr)
    } else { $g.DrawImage($ni, [int]($bx + 40 - $iw / 2), [int]($by + 38 - $ih / 2), $iw, $ih) }
    if ($n[2] -eq 'own' -or $n[2] -eq 'on') { $g.DrawRectangle((P 255 248 206 92 3), $bx + 2, $by + 2, 76, 72) }
    $lab = $(if ($n[2] -eq 'lock') { $grey } else { $white })
    Text $g $n[0] ($bx + 40) ($by + 78) 17 $lab -center
    $tag = $n[3]; if ($n[2] -eq 'on') { $tag += ' ON' } elseif ($n[2] -eq 'off') { $tag += ' OFF' }
    Text $g $tag ($bx + 88) ($by + 6) 17 $(if ($n[2] -eq 'on') { $crimson } elseif ($n[2] -eq 'lock') { $grey } else { $gold })
    if ($n[0] -eq "Smith's Start") {
      # only the four yellow corners of the quick slot's selection frame
      foreach ($q in @(@(0, 0), @(1, 0), @(0, 1), @(1, 1))) {
        $sx = $q[0] * 56; $sy = $q[1] * 56
        $g.DrawImage($corner, (New-Object System.Drawing.Rectangle ($bx - 6 + $q[0] * 64), ($by - 6 + $q[1] * 60), 28, 28), (New-Object System.Drawing.Rectangle $sx, $sy, 26, 26), [System.Drawing.GraphicsUnit]::Pixel)
      }
    }
    $k++
  }
  $c++
}
Draw-Plate $g 60 800 1160 128
Text $g "Smith's Start   0/3" 96 818 30 $gold
Text $g "The starting weapon starts one level up per rank.   Next: 5 Moon Shards" 96 862 23 $white
Text $g "Cross: buy     Square: switch on/off     L1/R1: rank" 96 892 20 $grey
$g.Dispose(); $bmp.Save("$out\tree_chart.png", [System.Drawing.Imaging.ImageFormat]::Png); "wrote tree_chart.png"
