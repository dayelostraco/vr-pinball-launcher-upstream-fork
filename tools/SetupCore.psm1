Set-StrictMode -Version 2

function Read-SetupConfig([string]$LauncherDirectory) {
    $path = Join-Path $LauncherDirectory 'launcher-config.json'
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) { return [pscustomobject]@{ vpinballExecutable=''; tablesDirectory=''; searchSubdirectories=$true } }
    $config = [IO.File]::ReadAllText($path) | ConvertFrom-Json -ErrorAction Stop
    if (!$config -or $config -is [array] -or $config -is [string] -or $config -is [ValueType]) { throw 'Launcher configuration must be a JSON object. The original file was not changed.' }
    return $config
}

function Get-SetupValue($Object, [string]$Name, $Default = '') {
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $Default
}

function Resolve-SetupPath([string]$Path, [string]$BaseDirectory) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    if (![IO.Path]::IsPathRooted($expanded)) { $expanded = Join-Path $BaseDirectory $expanded }
    return [IO.Path]::GetFullPath($expanded)
}

function Get-SetupVpxTarget([string]$Runner, [string]$ExplicitTarget = '') {
    if (!$Runner) { return [pscustomobject]@{ Runner=''; Target=$ExplicitTarget; Kind='Not configured'; Evidence='' } }
    $native = [IO.Path]::GetFileName($Runner) -match '^VPinballX(?:_|64|\.exe)'
    if ($native) { return [pscustomobject]@{ Runner=$Runner; Target=$Runner; Kind='VPX directly'; Evidence='Executable name' } }
    $target = $ExplicitTarget; $evidence = 'Saved VPX target'
    if ([IO.Path]::GetFileName($Runner) -ieq 'VpxBackgroundInput.exe') {
        $sidecar = Join-Path ([IO.Path]::GetDirectoryName($Runner)) 'VpxBackgroundInput.vpx-path.txt'
        $source = [IO.Path]::ChangeExtension($Runner,'.cs')
        if (Test-Path -LiteralPath $sidecar -PathType Leaf) { $target = [IO.File]::ReadAllText($sidecar).Trim(); $evidence = $sidecar }
        elseif (Test-Path -LiteralPath $source -PathType Leaf) {
            $m = [regex]::Match([IO.File]::ReadAllText($source), 'const\s+string\s+VpxPath\s*=\s*@"([^"]+)"')
            if ($m.Success) { $target = $m.Groups[1].Value; $evidence = 'Legacy helper source (target still needs a launch test)' }
        }
    }
    return [pscustomobject]@{ Runner=$Runner; Target=$target; Kind='Launch helper'; Evidence=$evidence }
}

function Find-SetupVpx([string]$LauncherDirectory, $Config) {
    $runner = Resolve-SetupPath (Get-SetupValue $Config 'vpinballExecutable') $LauncherDirectory
    $resolved = Get-SetupVpxTarget $runner (Get-SetupValue $Config 'realVpinballExecutable')
    if ($resolved.Target -and (Test-Path -LiteralPath $resolved.Target -PathType Leaf)) { return $resolved.Target }
    $roots = @('C:\Visual Pinball','D:\Visual Pinball','C:\Games\Visual Pinball',"$env:ProgramFiles\Visual Pinball", "${env:ProgramFiles(x86)}\Visual Pinball")
    foreach ($root in $roots) {
        foreach ($name in @('VPinballX_BGFX64.exe','VPinballX_GL64.exe','VPinballX64.exe')) {
            $candidate = Join-Path $root $name
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
    return ''
}

function Read-SetupIni([string]$Path) {
    $values = @{}; $section = ''
    if ($Path -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
        foreach ($line in [IO.File]::ReadAllLines($Path)) {
            if ($line -match '^\s*\[([^]]+)\]') { $section=$matches[1] }
            elseif ($line -match '^\s*([^;#=][^=]*?)\s*=\s*(.*?)\s*$') { $values["$section/$($matches[1].Trim())"] = $matches[2] }
        }
    }
    return $values
}

function Get-SetupIniLocation([string]$VpxExecutable, [string]$AppDataDirectory = $env:APPDATA) {
    $root = if ($VpxExecutable) { [IO.Path]::GetDirectoryName($VpxExecutable) } else { '' }
    $candidates = @()
    if ($root) { $candidates += Join-Path $root 'VPinballX.ini' }
    $candidates += Join-Path $AppDataDirectory 'VPinballX\10.8\VPinballX.ini'
    $candidates += Join-Path $AppDataDirectory 'VPinballX\VPinballX.ini'
    # A runtime log is evidence only when its application path matches this VPX install.
    foreach ($log in @((Join-Path $AppDataDirectory 'VPinballX\10.8\vpinball.log'),(Join-Path $AppDataDirectory 'VPinballX\vpinball.log'))) {
        if (!(Test-Path -LiteralPath $log -PathType Leaf)) { continue }
        $lines = @(Get-Content -LiteralPath $log -Tail 2500)
        $start = -1
        for ($i=$lines.Count-1; $i -ge 0; $i--) { if ($lines[$i] -match 'Starting VPX -') { $start=$i; break } }
        if ($start -lt 0) { continue }
        $section = $lines[$start..($lines.Count-1)] -join "`n"
        $app = [regex]::Match($section,'Application path:\s*([^\r\n]+)')
        $ini = [regex]::Match($section,'Settings file was loaded from\s+([^\r\n]+)')
        if ($app.Success -and $ini.Success -and $root -and $app.Groups[1].Value.Trim().TrimEnd('\') -ieq $root.TrimEnd('\')) {
            $path = $ini.Groups[1].Value.Trim().Trim("'")
            if (Test-Path -LiteralPath $path -PathType Leaf) { return [pscustomobject]@{ Path=$path; Verified=$true; Evidence='Confirmed by latest matching VPX log'; Candidates=@($candidates | Where-Object {Test-Path -LiteralPath $_ -PathType Leaf}) } }
        }
    }
    $existing = @($candidates | Where-Object {Test-Path -LiteralPath $_ -PathType Leaf} | Select-Object -Unique)
    $path = if ($existing.Count) {$existing[0]} else {''}
    return [pscustomobject]@{ Path=$path; Verified=$false; Evidence='Candidate only; launch a table to confirm which INI VPX uses'; Candidates=$existing }
}

function Get-SetupHealth([string]$LauncherDirectory, $Config, [string]$VpxExecutable = '', [string]$TablesDirectory = '') {
    $rows = [Collections.Generic.List[object]]::new()
    function Add-Row($Name,$Status,$Details,$Path='',$Blocking=$false) { $rows.Add([pscustomobject]@{ Component=$Name; Status=$Status; Details=$Details; Path=$Path; Blocking=$Blocking }) }
    $runner = Resolve-SetupPath (Get-SetupValue $Config 'vpinballExecutable') $LauncherDirectory
    $target = Get-SetupVpxTarget $runner (Get-SetupValue $Config 'realVpinballExecutable')
    if (!$VpxExecutable) { $VpxExecutable=$target.Target }
    if (!$TablesDirectory) { $TablesDirectory=Resolve-SetupPath (Get-SetupValue $Config 'tablesDirectory') $LauncherDirectory }
    $runnerFound = $runner -and (Test-Path -LiteralPath $runner -PathType Leaf)
    Add-Row 'Launch program' $(if($runnerFound){'Found'}else{'Missing'}) $target.Kind $runner (!$runnerFound)
    if($target.Kind -eq 'Launch helper'){Add-Row 'Helper target' 'Needs testing' $target.Evidence $target.Target}
    $vpxFound = $VpxExecutable -and (Test-Path -LiteralPath $VpxExecutable -PathType Leaf)
    $version = if($vpxFound){[Diagnostics.FileVersionInfo]::GetVersionInfo($VpxExecutable).FileVersion}else{''}
    Add-Row 'VPX executable' $(if($vpxFound){'Found'}else{'Missing'}) $(if($version){"Version $version"}else{'Select the actual VPX executable, separately from a helper'}) $VpxExecutable (!$vpxFound)
    $tablesFound = $TablesDirectory -and (Test-Path -LiteralPath $TablesDirectory -PathType Container)
    Add-Row 'Tables folder' $(if($tablesFound){'Found'}else{'Missing'}) 'Table INIs and scripts remain authoritative; this report does not change them.' $TablesDirectory (!$tablesFound)
    foreach($pair in @(@('Table artwork and previews','tableMediaDirectory','Media\Tables'),@('Wheel artwork','wheelDirectory','Media\Wheel'))){
        $media=Resolve-SetupPath (Get-SetupValue $Config $pair[1] $pair[2]) $LauncherDirectory
        Add-Row $pair[0] $(if($media -and (Test-Path -LiteralPath $media -PathType Container)){'Found'}else{'Needs testing'}) 'Optional artwork. Tables can be browsed without it; existing media paths are preserved.' $media
    }
    if (!$vpxFound) { return $rows.ToArray() }
    $root = [IO.Path]::GetDirectoryName($VpxExecutable)
    $iniLocation=Get-SetupIniLocation $VpxExecutable
    Add-Row 'VPX settings' $(if($iniLocation.Verified){'Found'}else{'Needs testing'}) $iniLocation.Evidence $iniLocation.Path
    $settings=Read-SetupIni $iniLocation.Path
    $vr=Get-SetupValue ([pscustomobject]$settings) 'PlayerVR/AskToTurnOn'
    Add-Row 'VR mode' 'Needs testing' $(if($vr -eq '0'){'Always-on VR configured; headset/runtime still needs a launch test'}elseif($vr -eq '2'){'Detected INI has VR turned off; verify the intended INI before changing it'}else{'Use a table test to confirm the OpenXR runtime and headset'}) $iniLocation.Path
    $roms=Join-Path $root 'VPinMAME\roms'
    try { $registered=(Get-ItemProperty 'HKCU:\Software\Freeware\Visual PinMame\globals' -ErrorAction Stop).rompath; if($registered){$roms=($registered -split ';')[0]} } catch { }
    Add-Row 'ROM library' $(if(Test-Path -LiteralPath $roms -PathType Container){'Found'}else{'Needs testing'}) 'Table-local pinmame folders can override this library. ROM ZIP contents are not audited here.' $roms
    foreach ($pair in @(@('Native PinMAME','pinmame','plugin-pinmame64.dll'),@('Native Serum','serum','plugin-serum64.dll'),@('Native ScoreView','scoreview','plugin-scoreview64.dll'),@('Native FlexDMD','flexdmd','plugin-flexdmd64.dll'),@('Native PuP','pup','plugin-pup64.dll'),@('Native B2S','b2s','plugin-b2s64.dll'))) {
        $file=Join-Path $root ("plugins\{0}\{1}" -f $pair[1],$pair[2]);$found=Test-Path -LiteralPath $file -PathType Leaf
        $key='Plugin.'+$pair[1]+'/Enable';$value=Get-SetupValue ([pscustomobject]$settings) $key
        Add-Row $pair[0] $(if($found){'Found'}else{'Needs testing'}) $(if(!$found){'Not detected; needed only by tables that use it'}elseif($value -eq '0'){'Installed, disabled globally; table INIs may enable it'}else{'Installed; presence does not confirm table compatibility or display routing'}) $file
    }
    foreach ($pair in @(@('Legacy VPinMAME','VPinMAME\VPinMAME64.dll'),@('Legacy FlexDMD','VPinMAME\FlexDMD.dll'),@('External DMD settings','VPinMAME\DmdDevice.ini'))) {
        $file=Join-Path $root $pair[1]
        Add-Row $pair[0] $(if(Test-Path -LiteralPath $file -PathType Leaf){'Found'}else{'Needs testing'}) 'Separate from native plugins; COM registration and per-table behavior require testing.' $file
    }
    $profiles=@(Get-SetupValue $Config 'vpxProfiles' @())
    foreach ($profile in $profiles) {
        if (!$profile) {continue}
        $exe=Resolve-SetupPath (Get-SetupValue $profile 'executable') $LauncherDirectory
        Add-Row ('Profile: '+(Get-SetupValue $profile 'name')) $(if($exe -and (Test-Path -LiteralPath $exe -PathType Leaf)){'Found'}else{'Needs testing'}) 'Existing profile and table assignments will be preserved.' $exe
    }
    Add-Row 'Controls, audio and DMD' 'Needs testing' 'Use a selected table to confirm input, comfortable volume, scoring and the correct DMD artwork.'
    return $rows.ToArray()
}

function Get-SetupPlan([string]$LauncherDirectory, $Config, [string]$VpxExecutable, [string]$TablesDirectory, [ValidateSet('Keep','Direct','Helper')][string]$LaunchMode='Keep', [bool]$EnableVR=$false) {
    $vpx=Resolve-SetupPath $VpxExecutable $LauncherDirectory; $tables=Resolve-SetupPath $TablesDirectory $LauncherDirectory
    if (!(Test-Path -LiteralPath $vpx -PathType Leaf) -or [IO.Path]::GetFileName($vpx) -notmatch '^VPinballX(?:_|64|\.exe)') { throw 'Choose the actual VPinballX executable, not a launcher or helper.' }
    if (!(Test-Path -LiteralPath $tables -PathType Container)) { throw 'Choose an existing tables folder.' }
    $next=$Config | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $oldRunner=Resolve-SetupPath (Get-SetupValue $Config 'vpinballExecutable') $LauncherDirectory
    $oldTarget=Get-SetupVpxTarget $oldRunner (Get-SetupValue $Config 'realVpinballExecutable')
    $runner=$oldRunner
    if ($LaunchMode -eq 'Direct') { $runner=$vpx }
    elseif ($LaunchMode -eq 'Helper') { $runner=Join-Path $LauncherDirectory 'tools\VpxBackgroundInput.exe' }
    elseif (!$runner -or !(Test-Path -LiteralPath $runner -PathType Leaf)) { throw 'The current launch program is missing. Choose Direct or Background helper.' }
    elseif ($oldTarget.Kind -eq 'VPX directly') { $runner=$vpx }
    elseif (!$oldTarget.Target -or $oldTarget.Target -ine $vpx) { throw 'The existing helper target cannot be verified for this VPX path. Choose Direct or Background helper explicitly.' }
    $changes=[Collections.Generic.List[string]]::new()
    foreach ($item in @(@('vpinballExecutable',$runner),@('realVpinballExecutable',$vpx),@('tablesDirectory',$tables))) {
        $label=@{vpinballExecutable='Launch program';realVpinballExecutable='Actual VPX executable';tablesDirectory='Tables folder'}[$item[0]]
        if ((Get-SetupValue $Config $item[0]) -cne $item[1]) { $changes.Add("${label}: $(Get-SetupValue $Config $item[0]) -> $($item[1])") }
        $next | Add-Member -NotePropertyName $item[0] -NotePropertyValue $item[1] -Force
    }
    if ($LaunchMode -eq 'Helper') { $changes.Add("Build/replace background-input helper and target file in $(Join-Path $LauncherDirectory 'tools'). Existing files will be backed up.") }
    $ini=Get-SetupIniLocation $vpx
    if ($EnableVR) {
        if (!$ini.Verified) { throw 'The active INI is not confirmed. Test a table first, then refresh health before enabling VR.' }
        $changes.Add("VPX settings: $($ini.Path) [PlayerVR] AskToTurnOn -> 0 (always VR)")
    }
    return [pscustomobject]@{ Config=$next; Changes=$changes.ToArray(); VpxExecutable=$vpx; ConfigPath=(Join-Path $LauncherDirectory 'launcher-config.json'); IniPath=$ini.Path; EnableVR=$EnableVR; InstallHelper=($LaunchMode -eq 'Helper'); LauncherDirectory=$LauncherDirectory; OriginalConfigJson=($Config|ConvertTo-Json -Depth 30) }
}

function Set-SetupVrIni([string]$Path) {
    # Preserve every original byte outside the single setting/section insertion.
    $bytes=[IO.File]::ReadAllBytes($Path);$prefix=[byte[]]@();$offset=0;$encoding=[Text.Encoding]::GetEncoding(28591)
    if($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191){$prefix=[byte[]]@(239,187,191);$offset=3}
    elseif($bytes.Length -ge 2 -and $bytes[0] -eq 255 -and $bytes[1] -eq 254){$prefix=[byte[]]@(255,254);$offset=2;$encoding=[Text.Encoding]::Unicode}
    elseif($bytes.Length -ge 2 -and $bytes[0] -eq 254 -and $bytes[1] -eq 255){$prefix=[byte[]]@(254,255);$offset=2;$encoding=[Text.Encoding]::BigEndianUnicode}
    $text=$encoding.GetString($bytes,$offset,$bytes.Length-$offset);$newline=if($text.Contains("`r`n")){"`r`n"}else{"`n"}
    $section=[regex]::Match($text,'(?ims)^\[PlayerVR\](?:\r?\n|\z).*?(?=^\[|\z)')
    if ($section.Success) {
        $replacement=$section.Value
        if ($replacement -match '(?m)^\s*AskToTurnOn\s*=') { $replacement=[regex]::Replace($replacement,'(?im)^(\s*AskToTurnOn\s*=)[^\r\n]*','$1 0') }
        else { $replacement=$replacement.TrimEnd("`r","`n")+$newline+'AskToTurnOn = 0'+$newline+$newline }
        $text=$text.Substring(0,$section.Index)+$replacement+$text.Substring($section.Index+$section.Length)
    } else { $text+=$newline+'[PlayerVR]'+$newline+'AskToTurnOn = 0'+$newline }
    [IO.File]::WriteAllBytes($Path,[byte[]]($prefix+$encoding.GetBytes($text)))
}

function Save-SetupPlan($Plan) {
    if (Get-Process -Name 'vr-launch','VPinballX_BGFX64','VPinballX_GL64','VPinballX64' -ErrorAction SilentlyContinue) { throw 'Close the launcher and VPX before applying setup changes.' }
    if (Test-Path -LiteralPath $Plan.ConfigPath -PathType Leaf) {
        $latest=Read-SetupConfig $Plan.LauncherDirectory
        if(($latest|ConvertTo-Json -Depth 30) -cne $Plan.OriginalConfigJson){throw 'Configuration changed since the setup window opened. Close and reopen setup before applying.'}
    }
    $backup=Join-Path $Plan.LauncherDirectory ('SetupBackups\'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    $originalConfig=$null; $originalIni=$null
    if (Test-Path -LiteralPath $Plan.ConfigPath) { $originalConfig=[IO.File]::ReadAllBytes($Plan.ConfigPath); [IO.File]::WriteAllBytes((Join-Path $backup 'launcher-config.json'),$originalConfig) }
    if ($Plan.EnableVR) { $originalIni=[IO.File]::ReadAllBytes($Plan.IniPath); [IO.File]::WriteAllBytes((Join-Path $backup 'VPinballX.ini'),$originalIni) }
    $Plan.Changes | Set-Content -LiteralPath (Join-Path $backup 'changes.txt') -Encoding UTF8
    $helperOriginals=@{}
    if($Plan.InstallHelper){foreach($name in @('VpxBackgroundInput.exe','VpxBackgroundInput.vpx-path.txt')){$file=Join-Path $Plan.LauncherDirectory ('tools\'+$name);$helperOriginals[$file]=if(Test-Path -LiteralPath $file -PathType Leaf){[IO.File]::ReadAllBytes($file)}else{$null}}}
    try {
        if ($Plan.InstallHelper) {
            & (Join-Path $Plan.LauncherDirectory 'tools\install-vpx-background-input.ps1') -VpxExecutable $Plan.VpxExecutable -DestinationDirectory (Join-Path $Plan.LauncherDirectory 'tools') | Out-Null
        }
        if ($Plan.EnableVR) { Set-SetupVrIni $Plan.IniPath }
        $temporary=$Plan.ConfigPath+'.setup-tmp'
        [IO.File]::WriteAllText($temporary,($Plan.Config | ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $Plan.ConfigPath) { [IO.File]::Replace($temporary,$Plan.ConfigPath,(Join-Path $backup 'config-before-atomic-replace.json')) } else { [IO.File]::Move($temporary,$Plan.ConfigPath) }
    } catch {
        if ($null -ne $originalConfig) { [IO.File]::WriteAllBytes($Plan.ConfigPath,$originalConfig) }
        if ($null -ne $originalIni) { [IO.File]::WriteAllBytes($Plan.IniPath,$originalIni) }
        foreach($file in $helperOriginals.Keys){if($null -ne $helperOriginals[$file]){[IO.File]::WriteAllBytes($file,$helperOriginals[$file])}elseif(Test-Path -LiteralPath $file -PathType Leaf){Remove-Item -LiteralPath $file -Force}}
        throw
    }
    return $backup
}

function Quote-SetupArgument([string]$Value) {
    # Windows CommandLineToArgvW quoting, including embedded quotes and trailing backslashes.
    return '"'+[regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'
}

function Get-SetupTestCommand($Config,[string]$Table,[string]$LauncherDirectory) {
    $Table=Resolve-SetupPath $Table $LauncherDirectory
    if (!(Test-Path -LiteralPath $Table -PathType Leaf) -or [IO.Path]::GetExtension($Table) -ine '.vpx') { throw 'Choose an existing .vpx table.' }
    $runner=Resolve-SetupPath (Get-SetupValue $Config 'vpinballExecutable') $LauncherDirectory
    $working=[IO.Path]::GetDirectoryName($runner);$ini='';$profileName='Default'
    foreach($assignment in @(Get-SetupValue $Config 'tableProfiles' @())) {
        if ((Get-SetupValue $assignment 'table') -ine [IO.Path]::GetFileNameWithoutExtension($Table)) {continue}
        foreach($profile in @(Get-SetupValue $Config 'vpxProfiles' @())) {
            if((Get-SetupValue $profile 'name') -ine (Get-SetupValue $assignment 'profile')){continue}
            $runner=Resolve-SetupPath (Get-SetupValue $profile 'executable') $LauncherDirectory
            $ini=Get-SetupValue $profile 'iniFile';$working=Get-SetupValue $profile 'workingDirectory';$profileName=Get-SetupValue $profile 'name'
            if($working -eq 'table'){$working=[IO.Path]::GetDirectoryName($Table)}elseif(!$working){$working=[IO.Path]::GetDirectoryName($runner)}
            break
        }
        break
    }
    if (!(Test-Path -LiteralPath $runner -PathType Leaf)) {throw 'The selected launch program does not exist.'}
    $arguments='-Play '+(Quote-SetupArgument $Table)
    if($ini){$arguments='-Ini '+(Quote-SetupArgument $ini)+' '+$arguments}
    return [pscustomobject]@{ Executable=$runner; Arguments=$arguments; WorkingDirectory=$working; Profile=$profileName; Table=$Table }
}

function Get-SetupStatePath {
    return Join-Path $env:USERPROFILE 'AppData\LocalLow\DefaultCompany\vr-launch\state.json'
}

function Assert-SetupClosed {
    if(Get-Process -Name 'vr-launch','VPinballX_BGFX64','VPinballX_GL64','VPinballX64' -ErrorAction SilentlyContinue){throw 'Close the launcher and VPX before exporting or restoring a backup.'}
}

function Get-SetupBytesHash([byte[]]$Bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','')}finally{$sha.Dispose()}
}

function Test-SetupBackupJson([string]$Name,[byte[]]$Bytes) {
    $value=[Text.Encoding]::UTF8.GetString($Bytes).TrimStart([char]0xFEFF) | ConvertFrom-Json -ErrorAction Stop
    if(!$value -or $value -is [array] -or $value -is [string] -or $value -is [ValueType]){throw "Invalid JSON object: $Name"}
    if($Name -eq 'state.json' -and ((Get-SetupValue $value 'version' 0) -ne 1 -or $null -eq $value.PSObject.Properties['favorites'] -or $null -eq $value.PSObject.Properties['plays'])){throw 'Unsupported or incomplete player history.'}
    if($Name -eq 'state.json'){
        if($value.favorites -isnot [array] -or $value.plays -isnot [array]){throw 'History favorites and plays must be arrays.'}
        foreach($favorite in $value.favorites){if($favorite -isnot [string]){throw 'Invalid favorite path.'}}
        foreach($play in $value.plays){if((Get-SetupValue $play 'path' $null) -isnot [string] -or (Get-SetupValue $play 'count' -1) -isnot [ValueType] -or (Get-SetupValue $play 'count' -1) -lt 0){throw 'Invalid play record.'}}
        if($value.PSObject.Properties['launches']){if($null -ne $value.launches -and $value.launches -isnot [array]){throw 'Launch history must be an array.'};foreach($launch in $value.launches){if((Get-SetupValue $launch 'path' $null) -isnot [string]){throw 'Invalid launch record.'}}}
    }
    return $value
}

function Export-SetupBackup([string]$LauncherDirectory,[string]$Destination,[string]$StatePath=(Get-SetupStatePath)) {
    Assert-SetupClosed
    Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
    if(Test-Path -LiteralPath $Destination){throw 'Choose a new backup filename; an existing file will not be overwritten.'}
    $files=@{};$configPath=Join-Path $LauncherDirectory 'launcher-config.json'
    if(!(Test-Path -LiteralPath $configPath -PathType Leaf)){throw 'No launcher configuration to export.'}
    $files['launcher-config.json']=[IO.File]::ReadAllBytes($configPath)
    if(Test-Path -LiteralPath $StatePath -PathType Leaf){$files['state.json']=[IO.File]::ReadAllBytes($StatePath)}
    $hashes=[ordered]@{}
    foreach($name in $files.Keys){$null=Test-SetupBackupJson $name $files[$name];$hashes[$name]=Get-SetupBytesHash $files[$name]}
    $manifest=[ordered]@{format='VRPinballLauncherBackup';version=1;createdUtc=[DateTime]::UtcNow.ToString('o');files=$hashes}
    $files['manifest.json']=[Text.Encoding]::UTF8.GetBytes(($manifest|ConvertTo-Json -Depth 8))
    $archive=$null
    try{
        $archive=[IO.Compression.ZipFile]::Open($Destination,[IO.Compression.ZipArchiveMode]::Create)
        foreach($name in $files.Keys){$entry=$archive.CreateEntry($name);$stream=$entry.Open();try{$stream.Write($files[$name],0,$files[$name].Length)}finally{$stream.Dispose()}}
    }catch{if($archive){$archive.Dispose();$archive=$null};if(Test-Path -LiteralPath $Destination){Remove-Item -LiteralPath $Destination -Force};throw}
    finally{if($archive){$archive.Dispose()}}
    return $Destination
}

function Read-SetupBackup([string]$Path) {
    Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
    $archive=[IO.Compression.ZipFile]::OpenRead($Path);$files=@{}
    try{
        if($archive.Entries.Count -gt 3){throw 'Unexpected backup contents.'}
        foreach($entry in $archive.Entries){
            $name=$entry.FullName
            if($name -cnotin @('manifest.json','launcher-config.json','state.json') -or $files.ContainsKey($name) -or $entry.Length -gt 10MB){throw 'Unexpected, duplicate, or oversized backup entry.'}
            $stream=$entry.Open();$memory=[IO.MemoryStream]::new()
            try{$buffer=New-Object byte[] 8192;while(($count=$stream.Read($buffer,0,$buffer.Length)) -gt 0){if($memory.Length+$count -gt 10MB){throw 'Backup entry exceeds limit.'};$memory.Write($buffer,0,$count)};$files[$name]=$memory.ToArray()}finally{$stream.Dispose();$memory.Dispose()}
        }
    }finally{$archive.Dispose()}
    if(!$files.ContainsKey('manifest.json') -or !$files.ContainsKey('launcher-config.json')){throw 'Incomplete launcher backup.'}
    $manifest=Test-SetupBackupJson 'manifest.json' $files['manifest.json']
    if((Get-SetupValue $manifest 'format') -cne 'VRPinballLauncherBackup' -or (Get-SetupValue $manifest 'version' 0) -ne 1){throw 'Unsupported backup format.'}
    $hashes=Get-SetupValue $manifest 'files'
    foreach($name in $files.Keys){if($name -eq 'manifest.json'){continue};if((Get-SetupValue $hashes $name) -cne (Get-SetupBytesHash $files[$name])){throw "Backup checksum failed: $name"};$null=Test-SetupBackupJson $name $files[$name]}
    foreach($property in $hashes.PSObject.Properties){if(!$files.ContainsKey($property.Name) -or $property.Name -eq 'manifest.json'){throw 'Manifest references an unexpected file.'}}
    return [pscustomobject]@{Files=$files;CreatedUtc=(Get-SetupValue $manifest 'createdUtc');Config=(Test-SetupBackupJson 'launcher-config.json' $files['launcher-config.json'])}
}

function New-SetupRestorePlan([string]$LauncherDirectory,[string]$ArchivePath,[bool]$RestoreConfig=$true,[bool]$RestoreHistory=$true,[bool]$KeepMachinePaths=$true,[string]$StatePath=(Get-SetupStatePath)) {
    $backup=Read-SetupBackup $ArchivePath;$files=@{};$changes=[Collections.Generic.List[string]]::new()
    if($RestoreConfig){
        $config=$backup.Config
        if($KeepMachinePaths){
            $current=Read-SetupConfig $LauncherDirectory
            foreach($name in @('vpinballExecutable','realVpinballExecutable','tablesDirectory','wheelDirectory','tableMediaDirectory','enableControllerBridge','controllerBridgePath','controllerBridgeArgs','controllerBridgeWorkingDir','vpxProfiles','tableProfiles')){
                if($current.PSObject.Properties[$name]){$config|Add-Member -NotePropertyName $name -NotePropertyValue $current.$name -Force}
                elseif($config.PSObject.Properties[$name]){$config.PSObject.Properties.Remove($name)}
            }
        }
        $files[(Join-Path $LauncherDirectory 'launcher-config.json')]=[Text.Encoding]::UTF8.GetBytes(($config|ConvertTo-Json -Depth 30))
        $changes.Add($(if($KeepMachinePaths){'Restore launcher preferences; keep this PC''s paths, controller launch settings, profiles and table assignments.'}else{'Replace launcher configuration, including paths, profiles, assignments and controller launch settings from the backup.'}))
        $changes.Add('Review restored executable paths before launching tables. External helpers and VPX add-ons are not included.')
    }
    if($RestoreHistory){if(!$backup.Files.ContainsKey('state.json')){throw 'This backup contains no player history. Uncheck history to restore settings only.'};$files[$StatePath]=$backup.Files['state.json'];$changes.Add('Replace favorites, play counts, history, browsing selection and table launch results. This does not merge history.')}
    if($files.Count -eq 0){throw 'Select settings or player history to restore.'}
    $originals=@{};foreach($path in $files.Keys){$originals[$path]=if(Test-Path -LiteralPath $path -PathType Leaf){[IO.File]::ReadAllBytes($path)}else{$null}}
    return [pscustomobject]@{LauncherDirectory=$LauncherDirectory;Files=$files;Originals=$originals;Changes=$changes.ToArray();CreatedUtc=$backup.CreatedUtc;ArchivePath=$ArchivePath}
}

function Save-SetupRestorePlan($Plan) {
    Assert-SetupClosed
    foreach($path in $Plan.Originals.Keys){$current=if(Test-Path -LiteralPath $path -PathType Leaf){[IO.File]::ReadAllBytes($path)}else{$null};$original=$Plan.Originals[$path];if(($null -eq $current) -ne ($null -eq $original) -or ($null -ne $current -and (Get-SetupBytesHash $current) -cne (Get-SetupBytesHash $original))){throw 'A destination changed after review. Review the restore again.'}}
    $directory=Join-Path $Plan.LauncherDirectory ('SetupBackups\restore-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    New-Item -ItemType Directory -Force $directory | Out-Null
    $Plan.Changes | Set-Content -LiteralPath (Join-Path $directory 'changes.txt') -Encoding UTF8
    @($Plan.Originals.Keys | ForEach-Object {[pscustomobject]@{Path=$_;Existed=($null -ne $Plan.Originals[$_])}}) | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $directory 'restore-destinations.json') -Encoding UTF8
    $written=[Collections.Generic.List[string]]::new()
    try{
        foreach($path in $Plan.Files.Keys){
            $original=$Plan.Originals[$path];if($null -ne $original){[IO.File]::WriteAllBytes((Join-Path $directory ([IO.Path]::GetFileName($path))),$original)}
            $parent=[IO.Path]::GetDirectoryName($path);New-Item -ItemType Directory -Force $parent | Out-Null
            $temp=$path+'.restore-'+[Guid]::NewGuid().ToString('N');[IO.File]::WriteAllBytes($temp,$Plan.Files[$path])
            try{if(Test-Path -LiteralPath $path){[IO.File]::Replace($temp,$path,(Join-Path $directory ('atomic-'+[IO.Path]::GetFileName($path))))}else{[IO.File]::Move($temp,$path)};$written.Add($path)}finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
        }
    }catch{foreach($path in $written){if($null -ne $Plan.Originals[$path]){[IO.File]::WriteAllBytes($path,$Plan.Originals[$path])}else{Remove-Item -LiteralPath $path -Force}};throw}
    return $directory
}

Export-ModuleMember -Function *-Setup*
