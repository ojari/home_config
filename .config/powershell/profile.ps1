#Import-Module oh-my-posh
#Set-PoshPrompt -Theme jari

Write-Host "profile.ps1..."

function prompt {
    $dir = (Get-Location).Path
    $dir = $dir.Replace("/home/jari/yocto/applications", "[A]")
    $dir = $dir.Replace("/home/jari/yocto/sources", "[S]")
    $dir = $dir.Replace("/home/jari/yocto/build", "[B]")
    $dir = $dir.Replace("/home/jari", "~")
    Write-Host $dir -ForegroundColor Cyan -NoNewline
    Write-Host (" [" + $(Get-GitStatus).Branch + "] ") -ForegroundColor Green -NoNewline
    return "> "
}

function rpi-log() {
    $data = ssh rpi "journalctl -x -o json" | ConvertFrom-json

    foreach ($line in $data) {
        Write-Host $line.PRIORITY $line.SYSLOG_IDENTIFIER $line.MESSAGE
    }
}

function ll {
    param(
        [string]$Path
    )
    # Get-ChildItem | Select-Object 'UnixMode', @{N="Time"; E={$_.LastWriteTime.ToString('dd/MM/yy hh:mm')}}, @{N="Size/k"; E={($_.Size / 1024).ToString("#.#")}}, 'Name'
    Get-ChildItem | Select-Object 'UnixMode', @{N="Size/k"; E={($_.Size / 1024).ToString("#.#")}}, 'Name'
}

function ems {
    emacs -nw --eval '(progn (magit-status) (delete-other-windows))'
}

function ed {
    param(
        [string]$file1,
        [string]$file2,
        [switch]$Dir
    )
    if ($Dir) {
        emacs -nw --eval ('(ediff-directories \"{0}\"  \"{1}\" nil)' -f $file1, $file2)
    }
    else {
        emacs -nw --eval ('(ediff-files \"{0}\"  \"{1}\")' -f $file1, $file2)
    }
}

function git-sync1 {
    git pull --rebase origin master
}

function git-sync2 {
    git push --force-with-lease
}

function git-backup {
    param(
        [String]$filename
    )
    if (-not(Test-Path "$filename.jari")) {
        Copy-Item $filename  "$filename.jari"
        git checkout $filename
    }
    else {
        Write-Host "Could not make backup $filename.jari exists!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    }
}

function git-diff {
    param(
        [String]$filename,
        [switch]$Code
    )
    if (Test-Path "$filename.jari") {
        if ($Code) {
            code -d {0} ('(ediff-files \"{0}\"  \"{1}\")' -f $filename, "$filename.jari")
        }
        else {
            emacs -nw --eval ('(ediff-files \"{0}\"  \"{1}\")' -f $filename, "$filename.jari")
        } 
    }
    else {
        Write-Host "There is no $filename.jari !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    }
}

function d {
    param(
        [String]$Command
    )
    bash -c "~/do.sh $Command"
}

function find-files {
    param(
        [String]$Text
    )

    Get-ChildItem -recurse | Select-String -Pattern $Text

    #Get-ChildItem -recurse |
    #  Where-Object { $_.Attributes -ne "Directory" } |
    #  ForEach-Object {
    #    if (Get-Content $_.FullName | Select-String -Pattern $Text) {
    #        Write-Host "- $_"
    #    }
    #}
}
