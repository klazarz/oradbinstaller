$installer = Join-Path $PSScriptRoot '..' 'install.ps1'
. $installer -NoRun

Describe 'Oracle Free Windows installer helpers' {
    It 'prefers Podman over Docker' {
        Mock Get-Command { [pscustomobject]@{ Source = 'mock' } } -ParameterFilter { $Name -eq 'podman' }
        Mock Get-Command { [pscustomobject]@{ Source = 'mock' } } -ParameterFilter { $Name -eq 'docker' }
        Get-ContainerRuntime | Should -Be 'podman'
    }

    It 'returns no runtime when neither executable exists' {
        Mock Get-Command { $null }
        Get-ContainerRuntime | Should -BeNullOrEmpty
    }

    It 'accepts a compliant Oracle password and rejects unsafe passwords' {
        Test-OraclePassword 'Oracle2026' | Should -BeTrue
        Test-OraclePassword 'simplepass' | Should -BeFalse
        Test-OraclePassword 'Oracle #2026' | Should -BeFalse
    }

    It 'validates portable container names and listener ports' {
        Test-Name 'oracle-free_1' | Should -BeTrue
        Test-Name 'bad name' | Should -BeFalse
        Test-Port '1521' | Should -BeTrue
        Test-Port '70000' | Should -BeFalse
    }

    It 'uses quick-mode defaults and asks only for the password' {
        Mock Read-YesNo { $false }
        Mock Read-OraclePassword { 'Oracle2026' }
        $config = Get-InstallConfiguration
        $config.ContainerName | Should -Be 'oracle-free'
        $config.VolumeName | Should -Be 'oracle-free-data'
        $config.Port | Should -Be '1521'
        $config.CharacterSet | Should -Be 'AL32UTF8'
        $config.ArchiveLog | Should -Be 'false'
        $config.ForceLogging | Should -Be 'false'
    }

    It 'uses advanced values when provided' {
        Mock Read-YesNo { $true }
        Mock Read-OraclePassword { 'Oracle2026' }
        Mock Read-ValidDefault {
            param($Prompt, $Default)
            switch ($Prompt) { 'Container name' { 'my-free' } 'Data volume name' { 'my-free-data' } default { '1522' } }
        }
        Mock Read-Default { 'WE8MSWIN1252' }
        $config = Get-InstallConfiguration
        $config.ContainerName | Should -Be 'my-free'
        $config.VolumeName | Should -Be 'my-free-data'
        $config.Port | Should -Be '1522'
        $config.CharacterSet | Should -Be 'WE8MSWIN1252'
        $config.ArchiveLog | Should -Be 'true'
        $config.ForceLogging | Should -Be 'true'
    }

    It 'prints a password-safe SQLcl connection command' {
        $config = @{ Port = '1522' }
        # This is the exact public connection shape; password must not occur in it.
        "sql sys@localhost:$($config.Port)/FREEPDB1 as sysdba" | Should -Be 'sql sys@localhost:1522/FREEPDB1 as sysdba'
    }

    It 'requires Java 17 even when SQLcl is already installed' {
        Mock Get-SqlclCommand { [pscustomobject]@{ Source = 'C:\\Tools\\sql.exe' } }
        Mock Get-JavaMajorVersion { 11 }
        Handle-Sqlcl | Should -BeFalse
        Assert-MockCalled Read-YesNo -Times 0
    }
}
