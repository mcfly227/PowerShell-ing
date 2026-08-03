for ($i = 0; $i -le 255; $i++) {
    Write-Host ("`e[38;5;${i}m " + $i.ToString().PadRight(4) + "`e[0m") -NoNewline
    if (($i + 1) % 16 -eq 0) { Write-Host "" }
}
