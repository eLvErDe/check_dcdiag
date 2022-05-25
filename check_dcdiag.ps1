#            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#                    Version 2, December 2004
#
# Copyright (C) 2022 Adam Cecile <acecile@letz-it>
#
# Everyone is permitted to copy and distribute verbatim or modified
# copies of this license document, and changing it is allowed as long
# as the name is changed.
#
#            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION
#
#  0. You just DO WHAT THE FUCK YOU WANT TO.

<#
.SYNOPSIS
  Run dcdiag.exe /test:SomeTest and parse output to return Nagios-style return code and about

.DESCRIPTION
  Run dcdiag.exe /test:SomeTest and parse output to return Nagios-style return code and about

.PARAMETER TestName
  Name of the test to be run, will be passed as /test:$TestName to dcdiag.exe

.PARAMETER TestArgs
  Optional array of additional arguments passed to the test, can be used for example
  with DNS test to run parametrized test like /DnsResolveExtName /DnsInternetName:www.google.lu

.EXAMPLE
  PS> .\check_dcdiag.ps1 -TestName SystemLogs

.EXAMPLE
  PS> .\check_dcdiag.ps1 -TestName Dns /DnsResolveExtName /DnsInternetName:www.google.lu

.EXAMPLE
  PS> .\check_dcdiag.ps1 -TestName Dns -TestArgs /DnsResolveExtName,/DnsInternetName:www.google.lu

.LINK
  https://github.com/eLvErDe/check_dcdiag
#>

Param(
    [Parameter(Mandatory = $false, ParameterSetName="TestName")] [string] $TestName,
    [Parameter(Mandatory = $false, ValueFromRemainingArguments = $true)] [string[]] $TestArgs
)

# Whole block below is just to get usage, did not find easier way with Powershell...
$ScriptFullPath = $MyInvocation.MyCommand.Path
$ScriptFilename = [io.path]::GetFileName($ScriptFullPath)
$ScriptHelpStr = Get-Help $MyInvocation.MyCommand.Definition | Out-String
$ScriptHelpStr -match '\r?\nSYNTAX\r?\n(?<syntax>.+)\r\n' | Out-Null
$ScriptUsage = $Matches.syntax.trim() -replace [Regex]::Escape($ScriptFullPath), $ScriptFilename

function Validate-Arguments {
  if ([string]::IsNullOrWhiteSpace($TestName)) {
    throw [System.ArgumentException]::New("Argument -TestName must be set and contains non-emtpy value, Usage: ${ScriptUsage}")
  }
  if ($TestArgs -ne $null) {
    foreach ($TestArg in $TestArgs) {
      if ([string]::IsNullOrWhiteSpace($TestArg)) {
        throw [System.ArgumentException]::New("Argument -TestArgs must contains non-emtpy values, Usage: ${ScriptUsage}")
      }
    }
  }
}

function Print-Exception-Details {
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [System.Management.Automation.ErrorRecord] $err
  )

  $formatString = "{0}{1}`n{2}`n" +
                  "    + CategoryInfo          : {3}`n" +
                  "    + FullyQualifiedErrorId : {4}`n"
  if ($err.InvocationInfo.MyCommand.Name) {
    $commandName = "$($err.InvocationInfo.MyCommand.Name) : "
  } else {
    $commandName = ''
  }
  $fields = $commandName,
            $err.Exception.Message,
            $err.InvocationInfo.PositionMessage,
            $err.CategoryInfo.ToString(),
            $err.FullyQualifiedErrorId
  return $formatString -f $fields
}

function Run-Dc-Diag {
  $DcDiagCmd = Get-Command 'dcdiag.exe' -ErrorAction Stop
  $DcDiagPath = $DcDiagCmd.Path

  $DcDiagToRun = "dcdiag /test:${TestName}"
  if ($TestArgs -ne $null) {
    $DcDiagToRun = "${DcDiagToRun} $($TestArgs -join ' ')"
  }
  $Output = & $DcDiagPath /test:${TestName} ${TestArgs} 2>&1
  if (!$?) {
    if ($Output -match '^Test not found') {
      throw [System.ArgumentException]::New("Non-existing test ${TestName} supplied for -TestName argument, output was: ${Output}")
    }
    if ($Output -match '^Invalid Syntax: Invalid option') {
      throw [System.ArgumentException]::New("Invalid argument(s) $($TestArgs -join ' ') provided to test ${TestName}, output was: ${Output}")
    }
    throw [System.ApplicationException]::New("Command ${DcDiagToRun} has crashed, output was: ${Output}")
  }

  [array] $TestResults = Parse-Dc-Diag-Output($Output)
 
  if ($TestResults.count -eq 0) {
    throw [System.ApplicationException]::New("Command ${DcDiagToRun} has crashed, no test result could be parsed from output")
  }

  $TestSucceeded = @()
  $TestFailed = @()
  $OutputForPrint = ''
  foreach ($TestResult in $TestResults) {
    if ($TestResult.Success) {
      $TestSucceeded += "$($TestResult.Name) on $($TestResult.Target)"
    } else {
      $TestFailed += "$($TestResult.Name) on $($TestResult.Target)"
      $OutputForPrint += [System.Environment]::NewLine
      $OutputForPrint += [System.Environment]::NewLine
      $OutputForPrint += $TestResult.Output
    }
  }


  if ($TestFailed.count -gt 0) {
    Write-Host "CRITICAL: $($TestFailed.count)/$($TestResults.count) tests failed: $($TestFailed -join ', '), run ${DcDiagToRun} /v to see more details"
    Write-Host ''
    Write-Host $OutputForPrint.Trim()
    exit 2
  } else {
    Write-Host "OK: $($TestSucceeded.count)/$($TestResults.count) tests succeeded: $($TestSucceeded -join ', ')"
    exit 0
  }

}

function Parse-Dc-Diag-Output {
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [System.Object[]] $Output
  )

  $Regex = [regex] '((?ms)Starting test.*?:\s+(.*?)[\r\n\s]+.*?([^\s]+)\s+(passed|warning|failed) test.*?$)'
  $AllMatches = $Regex.Matches(($Output | Out-String))

  $TestResults = New-Object System.Collections.Generic.List[System.Object]
  foreach ($Match in $AllMatches) {
    $TestOutput = $Match.Groups[1].Value 
    $TestResult = @{
      Output = ($TestOutput -replace "(?m)^\s*`r`n",'').Trim()
      Name = $Match.Groups[2].Value
      Target = $Match.Groups[3].Value
      Success = $Match.Groups[4].Value -eq "passed"
    }
    if (($TestResult.Target -eq $env:COMPUTERNAME) -and ($TestResult.Name -eq 'Connectivity')) {
      # Connectivity test on local machine is useless as this test is expected to be run remotely
    } else {
      $TestResults.Add($TestResult)
    }
  }
  return $TestResults
}

try {
  Validate-Arguments
  Run-Dc-Diag
} catch [System.ArgumentException] {
  Write-Host "UNKNOWN: $($Error[0])"
  exit 3
} catch [System.ApplicationException] {
  Write-Host "CRITICAL: $($Error[0])"
  exit 2
} catch {
  $ErrorClassName = $_.Exception.GetType().Name
  Write-Host "UNKNOWN: Script crashed: ${ErrorClassName}: $($Error[0])"
  $ErrorDetails = Print-Exception-Details($_)
  Write-Host ''
  Write-Host "$ErrorDetails"
  exit 3
}