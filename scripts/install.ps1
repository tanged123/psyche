# Use the active PowerShell host to locate redirected/OneDrive profile directories.
$ErrorActionPreference = 'Stop'
$installer = Join-Path $PSScriptRoot 'install.py'
$python = $null
$prefix = @()
foreach ($candidate in @('python3', 'python', 'py')) {
    if (Get-Command $candidate -ErrorAction SilentlyContinue) {
        $probe = @()
        if ($candidate -eq 'py') { $probe = @('-3') }
        try {
            & $candidate @probe -c 'import sys; sys.exit(sys.version_info < (3, 9))' 2>$null
            if ($LASTEXITCODE -eq 0) {
                $python = $candidate
                $prefix = $probe
                break
            }
        } catch {
            # Windows App Execution Aliases may exist without a working Python.
            continue
        }
    }
}
if (-not $python) {
    throw 'Python 3.9+ is required. Install Python from python.org or WinGet, then open a new terminal.'
}
$profileArgs = @('--powershell-profile', $PROFILE.CurrentUserAllHosts)
# An isolated target must never use the actual user's profile.
if (($args -contains '--home') -or ($args -match '^--home=')) {
    $profileArgs = @()
}
& $python @prefix $installer @profileArgs @args
exit $LASTEXITCODE
