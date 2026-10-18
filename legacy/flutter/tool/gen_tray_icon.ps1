# Generates a colored Windows tray icon (assets/tray/icon.ico) from the
# existing B&W "sc" mask (assets/tray/icon@2x.png), applying the brand
# green gradient defined in assets/branding/sc.svg. macOS keeps using
# the B&W icon.png as a template image — only Windows gets the colored
# variant, since Windows tray doesn't auto-tint icons the way macOS does.
#
# Run:  pwsh -File tool/gen_tray_icon.ps1
# Outputs: assets/tray/icon.ico (multi-resolution: 16, 24, 32, 48, 64)

param(
  [string]$Source = "assets/tray/icon@2x.png",
  [string]$Output = "assets/tray/icon.ico"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

# Brand gradient stops, matching `linearGradient` in assets/branding/sc.svg.
# Top → bottom: #96C94E → #609D4F → #27754D
function Get-GradientColor([double]$t) {
  if ($t -le 0.221154) {
    return @(150, 201, 78)
  } elseif ($t -le 0.605769) {
    $f = ($t - 0.221154) / (0.605769 - 0.221154)
    return @(
      [int][math]::Round((1 - $f) * 150 + $f * 96),
      [int][math]::Round((1 - $f) * 201 + $f * 157),
      [int][math]::Round((1 - $f) * 78 + $f * 79)
    )
  } elseif ($t -le 0.966346) {
    $f = ($t - 0.605769) / (0.966346 - 0.605769)
    return @(
      [int][math]::Round((1 - $f) * 96 + $f * 39),
      [int][math]::Round((1 - $f) * 157 + $f * 117),
      [int][math]::Round((1 - $f) * 79 + $f * 77)
    )
  } else {
    return @(39, 117, 77)
  }
}

function Convert-MaskToColored([System.Drawing.Bitmap]$src, [int]$size) {
  # First, scale the source mask down to the target size with high
  # quality so anti-aliased edges are preserved.
  $tmp = [System.Drawing.Bitmap]::new(
    $size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($tmp)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.Clear([System.Drawing.Color]::White)
  $g.DrawImage($src, 0, 0, $size, $size)
  $g.Dispose()

  $dst = [System.Drawing.Bitmap]::new(
    $size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)

  for ($y = 0; $y -lt $size; $y++) {
    $rgb = Get-GradientColor ([double]$y / [double]($size - 1))
    for ($x = 0; $x -lt $size; $x++) {
      $px = $tmp.GetPixel($x, $y)
      # Source is dark "sc" on white: invert luma so dark pixels become
      # opaque, light pixels become transparent. 0.299/0.587/0.114 is the
      # ITU-R BT.601 luma coefficients — picks up the anti-aliased greys
      # along the stroke edges with the right weighting.
      $luma = 0.299 * $px.R + 0.587 * $px.G + 0.114 * $px.B
      $alpha = [int][math]::Round(255 * (1.0 - $luma / 255.0))
      if ($alpha -le 0) { continue }
      $dst.SetPixel($x, $y,
        [System.Drawing.Color]::FromArgb($alpha, $rgb[0], $rgb[1], $rgb[2]))
    }
  }
  $tmp.Dispose()
  return $dst
}

function Get-PngBytes([System.Drawing.Bitmap]$bmp) {
  $ms = [System.IO.MemoryStream]::new()
  $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
  return $ms.ToArray()
}

# Resolve paths relative to script's repo root.
$repoRoot = Split-Path -Parent $PSScriptRoot
$srcPath = Join-Path $repoRoot $Source
$outPath = Join-Path $repoRoot $Output

if (-not (Test-Path $srcPath)) {
  throw "Source mask not found: $srcPath"
}

$src = [System.Drawing.Bitmap]::FromFile($srcPath)
try {
  $sizes = @(16, 24, 32, 48, 64)
  $pngs = @()
  foreach ($size in $sizes) {
    $bmp = Convert-MaskToColored $src $size
    $bytes = Get-PngBytes $bmp
    $bmp.Dispose()
    $pngs += , @{ Size = $size; Data = $bytes }
    Write-Host ("  {0,2}x{1,-2} -> {2,5} bytes" -f $size, $size, $bytes.Length)
  }
} finally {
  $src.Dispose()
}

# Build the ICO: 6-byte header, 16 bytes per directory entry, then PNG
# blobs in order. PNG-in-ICO is the modern format Windows Vista+ supports
# and is what we get from System.Drawing.Bitmap.Save(Png).
$out = [System.IO.MemoryStream]::new()
$bw = [System.IO.BinaryWriter]::new($out)
$bw.Write([UInt16]0)          # reserved
$bw.Write([UInt16]1)          # type = ICO
$bw.Write([UInt16]$pngs.Count)

$dataOffset = 6 + 16 * $pngs.Count
foreach ($p in $pngs) {
  $w = if ($p.Size -ge 256) { 0 } else { $p.Size }  # 0 = 256 in ICO spec
  $bw.Write([byte]$w)         # width
  $bw.Write([byte]$w)         # height
  $bw.Write([byte]0)          # colors
  $bw.Write([byte]0)          # reserved
  $bw.Write([UInt16]1)        # planes
  $bw.Write([UInt16]32)       # bpp
  $bw.Write([UInt32]$p.Data.Length)
  $bw.Write([UInt32]$dataOffset)
  $dataOffset += $p.Data.Length
}
foreach ($p in $pngs) {
  # Explicit (buffer, offset, count) overload — PowerShell can unwrap a
  # bare byte[] argument and dispatch to BinaryWriter.Write(byte) per
  # element, leaving only the first byte of each PNG in the file.
  $bw.Write([byte[]]$p.Data, 0, [int]$p.Data.Length)
}
$bw.Flush()
[System.IO.File]::WriteAllBytes($outPath, $out.ToArray())
$bw.Dispose()
$out.Dispose()

Write-Host ("Wrote {0} ({1} bytes)" -f $outPath, (Get-Item $outPath).Length)
