Write-Host "using home profile"

Set-PSReadLineOption -EditMode Emacs

Import-Module posh-git
# Import-Module oh-my-posh
# Set-Theme Paradox   # Paradox, Lambda

$env:EDITOR = "C:\\Program Files\\Emacs\\emacs-30.1\\bin\\emacs.exe"
set-alias -Name edge -Value 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'

Set-PSReadLineKeyHandler -Chord Ctrl+d -Function BackwardDeleteChar
Set-PSReadLineKeyHandler -Chord Ctrl+i -Function PreviousHistory
Set-PSReadLineKeyHandler -Chord Ctrl+k -Function NextHistory
Set-PSReadLineKeyHandler -Chord Ctrl+j -Function BackwardChar
Set-PSReadLineKeyHandler -Chord Ctrl+l -Function ForwardChar

function emacs() {
    param(
      [String] $argument
    )
    c:\usr\emacs-28.2\bin\runemacs.exe $argument
}

function nmake() {
    param(
      [String] $argument
    )
    c:\usr\nmake.exe /nologo $argument
}
