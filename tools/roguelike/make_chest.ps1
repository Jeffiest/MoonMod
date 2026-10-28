# Draws the Gauntlet's HUD chest (32x32) from a character grid: the Miracle cache a cursed floor pays.
param([string]$Out)
Add-Type -AssemblyName System.Drawing
$palette = @{
  '.' = $null
  'K' = @(255, 34, 18, 10)     # outline
  'D' = @(255, 96, 50, 22)     # dark wood
  'W' = @(255, 150, 86, 38)    # wood
  'L' = @(255, 200, 132, 62)   # light wood
  'O' = @(255, 146, 96, 18)    # dark gold
  'G' = @(255, 226, 178, 52)   # gold
  'Y' = @(255, 255, 234, 140)  # gold highlight
  'S' = @(255, 255, 255, 230)  # sparkle
}
$rows = @(
  '................................',
  '................................',
  '.........................S......',
  '........................SYS.....',
  '.........................S......',
  '......KKKKKKKKKKKKKKKKKKKK......',
  '.....KLLLLLGYGLLLLLLGYGLLLK.....',
  '....KLLWWWWGYGWWWWWWGYGWWWLK....',
  '....KLWWWWWGYGWWWWWWGYGWWWWK....',
  '....KWWWWWWGGGWWWWWWGGGWWWWK....',
  '....KWWWWWWGGGWWWWWWGGGWWWWK....',
  '....KDDDDDDOGODDDDDDOGODDDDK....',
  '...KKKKKKKKKKKKKKKKKKKKKKKKKK...',
  '...KGGGGGGGGGGGKKKKGGGGGGGGGK...',
  '...KYYYYYYYYYYKGYYGKYYYYYYYYK...',
  '...KOOOOOOOOOOKGYYGKOOOOOOOOK...',
  '...KKKKKKKKKKKKGOOGKKKKKKKKKK...',
  '...KLLLLLGYGLLKGKKGKLLGYGLLLK...',
  '...KLWWWWGYGWWKKGGKKWWGYGWWLK...',
  '...KWWWWWGYGWWWKKKKWWWGYGWWWK...',
  '...KWWWWWGGGWWWWWWWWWWGGGWWWK...',
  '...KWWWWWGGGWWWWWWWWWWGGGWWWK...',
  '...KWWWWWGGGWWWWWWWWWWGGGWWWK...',
  '...KDWWWWGGGWWWWWWWWWWGGGWWDK...',
  '...KDDDDDOGODDDDDDDDDDOGODDDK...',
  '...KDDDDDOGODDDDDDDDDDOGODDDK...',
  '...KKKKKKKKKKKKKKKKKKKKKKKKKK...',
  '....KKKKKKKKKKKKKKKKKKKKKKKK....',
  '................................',
  '................................',
  '................................',
  '................................'
)
$bmp = New-Object System.Drawing.Bitmap 32, 32, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
for ($y = 0; $y -lt 32; $y++) {
  $row = $rows[$y].PadRight(32, '.')
  for ($x = 0; $x -lt 32; $x++) {
    $c = $palette[[string]$row[$x]]
    if ($c) { $bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($c[0], $c[1], $c[2], $c[3])) }
    else { $bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(0, 0, 0, 0)) }
  }
}
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$big = New-Object System.Drawing.Bitmap 256, 256
$g = [System.Drawing.Graphics]::FromImage($big)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
$g.Clear([System.Drawing.Color]::FromArgb(255, 90, 70, 50))
$g.DrawImage($bmp, 0, 0, 256, 256)
$big.Save(($Out -replace '\.png$', '-preview.png'), [System.Drawing.Imaging.ImageFormat]::Png)
"wrote $Out"
