# Description

This project is a Nagios-style monitoring check to run dcdiag.exe on Active Directory servers.

It is highly inspired from [check \_ad.vbs](https://exchange.nagios.org/directory/Plugins/Operating-Systems/Windows/Active-Directory-(AD)-Check/details) but fully rewritten using PowerShell to provide cleaner code and allow passing additional arguments.

**Only tested on Windows Server 2019 English, most likely works on other version, most unlikely works on different language**

# Features

* Clean PowerShell code (I am not a Window guy but I did try to do my best)
* Attempt to handle most errors correctly (bad arguments => UNKNOWN, dcdiag.exe crash => CRITICAL)
* Pass additional arguments to test, e.g: to be able to run DNS sub-tests separately
* Logs failed test output, but  might be truncated depending on the monitoring app
* WTFPL license so you do whatever you want with this code

# Examples

Use `dcdiag.exe /h` to list existing tests and their description

Verify accounts privileges needed for replications:

```
.\check_dcdiag.ps1 -TestName NetLogons
```

```
CRITICAL: 1/1 tests failed: NetLogons on ADSRV03, run dcdiag /test:NetLogons /v to see more details

Starting test: NetLogons
         [ADSRV03] User credentials does not have permission to perform this
         operation.
         The account used for this test must have network logon privileges
         for this machine's domain.
         ......................... ADSRV03 failed test NetLogons
```

Verify DNS resolution with custom target:

```
.\check_dcdiag.ps1 -TestName DNS -TestArgs /DnsResolveExtName,/DnsInternetName:www.google.lu
```

Or

```
.\check_dcdiag.ps1 -TestName DNS /DnsResolveExtName /DnsInternetName:www.google.lu
```

```
OK: 2/2 tests succeeded: DNS on ADSRV03, DNS on ad.domain.com
```

Bad arguments:

```
.\check_dcdiag.ps1 -TestName Invalid
```

```
UNKNOWN: Non-existing test Invalid supplied for -TestName argument, output was: Test not found. Please re-enter a valid test name.
```

```
.\check_dcdiag.ps1 -TestName NetLogons -TestArgs abc
```

```
UNKNOWN: Invalid argument(s) abc provided to test NetLogons, output was: Invalid Syntax: Invalid option abc. Use dcdiag.exe /h for help.
```

# NSClient++ integration

Add the following settings in `nsclient.ini` to make it work:

```
[/settings/NRPE/server]
allow arguments = true

[/modules]
CheckExternalScripts = enabled

[/settings/external scripts]
allow arguments = true
timeout = 300

[/settings/external scripts/wrappings]
ps1=cmd /c echo scripts\\\\%SCRIPT% %ARGS%; exit($lastexitcode) | powershell.exe -command -

[/settings/external scripts/wrapped scripts]
check_dcdiag = custom\check_dcdiag.ps1 -TestName $ARG1$
check_dcdiag_custom_args = custom\check_dcdiag.ps1 -TestName $ARG1$ -TestArgs $ARG2$
```

And deploy `check_dcdiag.ps1` to `C:\Program Files\NSClient++\scripts\custom` and then restart service.

To reduce DNS test duration time, if using non-Microsoft DNS forwarders on your controllers, make sure to return proper REJECT on TCP/135 from your DNS forwarder to Active Directory controler, otherwise it will attempt to request them using RPC, considering it might be Windows servers and time out.

Also, running DnsForwarders test with non-Microsoft DNS forwarders will generate some RPC connection errors in System logs and will make SystemLog test turns critical, so you probably want to avoid DnsForwarders test if using non-Microsoft forwarders.
