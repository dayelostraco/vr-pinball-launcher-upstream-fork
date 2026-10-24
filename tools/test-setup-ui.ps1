$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('vpx-setup-ui-'+[Guid]::NewGuid().ToString('N'))
$tables=Join-Path $root 'Tables';New-Item -ItemType Directory -Force $root,$tables | Out-Null
$exe=Join-Path $root 'VPinballX_SETUP_TEST.exe';$source=Join-Path $root 'Fixture.cs'
[IO.File]::WriteAllText($source,'internal static class TestApp { static int Main() { System.Threading.Thread.Sleep(300); return 42; } }')
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:winexe "/out:$exe" $source
if($LASTEXITCODE -ne 0){throw 'UI fixture compile failed'}
[IO.File]::WriteAllText((Join-Path $tables 'Setup UI Test.vpx'),'A dummy fixture; never opened by VPX.')
$config=[ordered]@{vpinballExecutable=$exe;tablesDirectory=$tables;searchSubdirectories=$true}
[IO.File]::WriteAllText((Join-Path $root 'launcher-config.json'),($config|ConvertTo-Json))
$before=(Get-FileHash -LiteralPath (Join-Path $root 'launcher-config.json')).Hash
& (Join-Path $PSScriptRoot 'setup.ps1') -LauncherDirectory $root -SmokeTest
if((Get-FileHash -LiteralPath (Join-Path $root 'launcher-config.json')).Hash -ne $before){throw 'UI test modified configuration without Apply'}
Write-Output "PASS: configuration untouched. UI fixtures: $root"
