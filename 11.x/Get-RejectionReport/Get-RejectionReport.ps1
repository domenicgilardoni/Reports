param (
	[Parameter(Mandatory=$false)][int] $NumberOfDaysToReport = 7,
	[Parameter(Mandatory=$true)][string] $SMTPHost,
	[Parameter(Mandatory=$false)][string] $ReportSender = "NoSpamProxy Report Sender <nospamproxy@example.com>",
	[Parameter(Mandatory=$true)][string] $ReportRecipient,
	[Parameter(Mandatory=$false)][string] $ReportSubject = "Auswertung"
)

$reportFileName = $Env:TEMP + "\reject-analysis.html"
$totalRejected = 0
$tempRejected = 0
$permanentRejected = 0
$rdnsTempRejected = 0
$rblRejected = 0
$cyrenSpamRejected = 0
$cyrenAVRejected = 0
$surblRejected = 0
$characterSetRejected = 0
$headerFromRejected = 0
$wordRejected = 0
$rdnsPermanentRejected = 0
$decryptPolicyRejected = 0
$onBodyRejected = 0
$onEnvelopeRejected = 0
$dateStart = (Get-Date).AddDays(-$NumberOfDaysToReport)
$dateTo = Get-Date -format "dd.MM.yyyy"
$dateFrom = $dateStart.ToString("dd.MM.yyyy")

Write-Host "Getting MessageTracks from NoSpamProxy..."
$messageTracks = Get-NSPMessageTrack -From $dateStart -Status TemporarilyBlocked -Directions FromExternal |Get-NSPMessageTrackdetails

foreach ($item in $messageTracks)
{
	$totalRejected++
	$tempRejected++
	$tempvalidationentries = $item.Details.ValidationResult.ValidationEntries
	foreach ($tempvalidationentry in $tempvalidationentries)
	{
		if (($tempvalidationentry.Id -eq "reverseDnsLookup") -and ($tempvalidationentry.Decision -eq "RejectTemporarily" ))
		{
			$rdnsTempRejected++
			$onEnvelopeRejected++
		}
	}
}

$messageTracks = Get-NSPMessageTrack -From $dateStart -Status PermanentlyBlocked -Directions FromExternal |Get-NSPMessageTrackdetails

foreach ($item in $messageTracks)
{
	$totalRejected++
	$permanentRejected++
	$permanentvalidationentries = $item.Details.ValidationResult.ValidationEntries
	foreach ($permanentvalidationentry in $permanentvalidationentries)
	{
		if ($permanentvalidationentry.Id -eq "realtimeBlocklist" -and $permanentvalidationentry.Scl -gt 0)
		{
			$rblRejected++
			$onEnvelopeRejected++
		}
		if ($permanentvalidationentry.Id -eq "cyrenAction" -and $permanentvalidationentry.Decision -notcontains "Pass")
		{
			$cyrenAVRejected++
			$onBodyRejected++
		}
		if ($permanentvalidationentry.Id -eq "surblFilter" -and $permanentvalidationentry.Scl -gt 0)
		{
			$surblRejected++
			$onBodyRejected++
		}
		if ($permanentvalidationentry.Id -eq "cyrenFilter" -and $permanentvalidationentry.Scl -gt 0)
		{
			$cyrenSpamRejected++
			$onBodyRejected++
		}
		if ($permanentvalidationentry.Id -eq "characterSetFilter" -and $permanentvalidationentry.Scl -gt 0)
		{
			$characterSetRejected++
			$onBodyRejected++
		}
		if ($permanentvalidationentry.Id -eq "ensureHeaderFromIsExternal" -and $permanentvalidationentry.Scl -gt 0)
		{
			$headerFromRejected++
			$onBodyRejected++
		}
		if ($permanentvalidationentry.Id -eq "wordFilter" -and $permanentvalidationentry.Scl -gt 0)
		{
			$wordRejected++
			$onBodyRejected++
		}
		if (($permanentvalidationentry.Id -eq "reverseDnsLookup") -and ($permanentvalidationentry.Scl -gt 0))
		{
			$rdnsPermanentRejected++
			$onEnvelopeRejected++
		}
		if (($permanentvalidationentry.Id -eq "validateSignatureAndDecrypt") -and ($permanentvalidationentry.Decision -notcontains "Pass" ))
		{
			$decryptPolicyRejected++
			$onBodyRejected++
		}
	}
}

$outboundmessages = (Get-NSPMessageTrack -From $dateStart -Directions FromLocal).count
$inboundmessages = (Get-NSPMessageTrack -From $dateStart -Directions FromExternal).count
$mailsprocessed = $outboundmessages+$inboundmessages
$blockedpercentage = [Math]::Round($totalRejected/$inboundmessages*100,2)
$cyrenspamblockpercentage = [Math]::Round($cyrenSpamRejected/$totalRejected*100,2)
$cyrenavblockpercentage = [Math]::Round($cyrenAVRejected/$totalRejected*100,2)
$surblblockedpercentage = [Math]::Round($surblRejected/$totalRejected*100,2)
$charactersetblockedpercentage = [Math]::Round($characterSetRejected/$totalRejected*100,2)
$headerfromblockedpercentage = [Math]::Round($headerFromRejected/$totalRejected*100,2)
$wordrejectedblockedpercentage = [Math]::Round($wordRejected/$totalRejected*100,2)
$decryptpolicyblockedpercentage = [Math]::Round($decryptPolicyRejected/$totalRejected*100,2)
$rblRejectedpercentage = [Math]::Round($rblRejected/$totalRejected*100,2)
$rdnsPermanentRejectedpercentage = [Math]::Round($rdnsPermanentRejected/$totalRejected*100,2)

Write-Host " "
Write-Host "TemporaryReject Total:" $tempRejected
Write-Host "PermanentReject Total:" $permanentRejected
Write-Host "TotalReject:" $totalRejected
Write-Host " "
Write-Host "Sending E-Mail to " $ReportRecipient "..."

$htmlout = "<html>
		<head>
			<title>Auswertung der abgewiesenen E-Mails</title>
			<style>
      			table, td, th { border: 1px solid #00cc00; border-collapse: collapse; }
				th, td {padding-left:1em; padding-right:1em;}
				td:not(:first-child){text-align:right;}
				th {color:white;}
				#headerzeile         {background-color: #00cc00;}
    		</style>
		</head>
	<body style=font-family:arial>
		<table>
			<tr id=headerzeile><th>"+ $dateFrom +" bis "+ $dateTo +" ("+$NumberOfDaysToReport+" Tage)</th><th>Count</th><th>Percent</th></tr>
			<tr><td>Mails Processed</td><td>" + $mailsprocessed +"</td><td>&nbsp;</td></tr>
			<tr><td>Sent</td><td>" + $outboundmessages +"</td><td>&nbsp;</td></tr>
			<tr><td>Received</td><td>" + $inboundmessages +"</td><td>&nbsp;</td></tr>
			<tr><td>Mails blocked</td><td>" + $totalRejected +"</td><td>" + $blockedpercentage +" %</td></tr>
			<tr><td>Realtime Blocklist Check</td><td>" + $rblRejected +"</td><td>" + $rblRejectedpercentage +" %</td></tr>
			<tr><td>RDNS Check</td><td>" + $rdnsPermanentRejected +"</td><td>" + $rdnsPermanentRejectedpercentage +" %</td></tr>
			<tr><td>Cyren AntiSpam</td><td>" + $cyrenSpamRejected +"</td><td>" + $cyrenspamblockpercentage +" %</td></tr>
			<tr><td>Cyren Premium AntiVirus</td><td>" + $cyrenAVRejected +"</td><td>" + $cyrenavblockpercentage +" %</td></tr>
			<tr><td>Spam URI Realtime Blocklists</td><td>" + $surblRejected +"</td><td>" + $surblblockedpercentage +" %</td></tr>
			<tr><td>Allowed Unicode Character Sets</td><td>" + $characterSetRejected +"</td><td>" + $charactersetblockedpercentage +" %</td></tr>
			<tr><td>Prevent Owned Domains in HeaderFrom</td><td>" + $headerFromRejected +"</td><td>" + $headerfromblockedpercentage +" %</td></tr>
			<tr><td>Word Matching</td><td>" + $wordRejected +"</td><td>" + $wordrejectedblockedpercentage +" %</td></tr>
			<tr><td>DecryptPolicy Reject</td><td>" + $decryptPolicyRejected +"</td><td>" + $decryptpolicyblockedpercentage +" %</td></tr>
		</table>
	</body>
	</html>"

$htmlout | Out-File $reportFileName
Send-MailMessage -SmtpServer $SmtpHost -From $ReportSender -To $ReportRecipient -Subject $ReportSubject -Body "Im Anhang dieser E-Mail finden Sie den Bericht mit der Auswertung der abgewiesenen E-Mails." -Attachments $reportFileName
Write-Host "Doing some cleanup.."
Remove-Item $reportFileName
Write-Host "Done."


# SIG # Begin signature block
# MIIMSwYJKoZIhvcNAQcCoIIMPDCCDDgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU2l+06vngCpqVsLaMi+VTKfrA
# UyKgggmqMIIElDCCA3ygAwIBAgIOSBtqBybS6D8mAtSCWs0wDQYJKoZIhvcNAQEL
# BQAwTDEgMB4GA1UECxMXR2xvYmFsU2lnbiBSb290IENBIC0gUjMxEzARBgNVBAoT
# Ckdsb2JhbFNpZ24xEzARBgNVBAMTCkdsb2JhbFNpZ24wHhcNMTYwNjE1MDAwMDAw
# WhcNMjQwNjE1MDAwMDAwWjBaMQswCQYDVQQGEwJCRTEZMBcGA1UEChMQR2xvYmFs
# U2lnbiBudi1zYTEwMC4GA1UEAxMnR2xvYmFsU2lnbiBDb2RlU2lnbmluZyBDQSAt
# IFNIQTI1NiAtIEczMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAjYVV
# I6kfU6/J7TbCKbVu2PlC9SGLh/BDoS/AP5fjGEfUlk6Iq8Zj6bZJFYXx2Zt7G/3Y
# SsxtToZAF817ukcotdYUQAyG7h5LM/MsVe4hjNq2wf6wTjquUZ+lFOMQ5pPK+vld
# sZCH7/g1LfyiXCbuexWLH9nDoZc1QbMw/XITrZGXOs5ynQYKdTwfmOPLGC+MnwhK
# kQrZ2TXZg5J2Yl7fg67k1gFOzPM8cGFYNx8U42qgr2v02dJsLBkwXaBvUt/RnMng
# Ddl1EWWW2UO0p5A5rkccVMuxlW4l3o7xEhzw127nFE2zGmXWhEpX7gSvYjjFEJtD
# jlK4PrauniyX/4507wIDAQABo4IBZDCCAWAwDgYDVR0PAQH/BAQDAgEGMB0GA1Ud
# JQQWMBQGCCsGAQUFBwMDBggrBgEFBQcDCTASBgNVHRMBAf8ECDAGAQH/AgEAMB0G
# A1UdDgQWBBQPOueslJF0LZYCc4OtnC5JPxmqVDAfBgNVHSMEGDAWgBSP8Et/qC5F
# JK5NUPpjmove4t0bvDA+BggrBgEFBQcBAQQyMDAwLgYIKwYBBQUHMAGGImh0dHA6
# Ly9vY3NwMi5nbG9iYWxzaWduLmNvbS9yb290cjMwNgYDVR0fBC8wLTAroCmgJ4Yl
# aHR0cDovL2NybC5nbG9iYWxzaWduLmNvbS9yb290LXIzLmNybDBjBgNVHSAEXDBa
# MAsGCSsGAQQBoDIBMjAIBgZngQwBBAEwQQYJKwYBBAGgMgFfMDQwMgYIKwYBBQUH
# AgEWJmh0dHBzOi8vd3d3Lmdsb2JhbHNpZ24uY29tL3JlcG9zaXRvcnkvMA0GCSqG
# SIb3DQEBCwUAA4IBAQAVhCgM7aHDGYLbYydB18xjfda8zzabz9JdTAKLWBoWCHqx
# mJl/2DOKXJ5iCprqkMLFYwQL6IdYBgAHglnDqJQy2eAUTaDVI+DH3brwaeJKRWUt
# TUmQeGYyDrBowLCIsI7tXAb4XBBIPyNzujtThFKAzfCzFcgRCosFeEZZCNS+t/9L
# 9ZxqTJx2ohGFRYzUN+5Q3eEzNKmhHzoL8VZEim+zM9CxjtEMYAfuMsLwJG+/r/uB
# AXZnxKPo4KvcM1Uo42dHPOtqpN+U6fSmwIHRUphRptYCtzzqSu/QumXSN4NTS35n
# fIxA9gccsK8EBtz4bEaIcpzrTp3DsLlUo7lOl8oUMIIFDjCCA/agAwIBAgIMUfr8
# J+jCyr4Ay7YNMA0GCSqGSIb3DQEBCwUAMFoxCzAJBgNVBAYTAkJFMRkwFwYDVQQK
# ExBHbG9iYWxTaWduIG52LXNhMTAwLgYDVQQDEydHbG9iYWxTaWduIENvZGVTaWdu
# aW5nIENBIC0gU0hBMjU2IC0gRzMwHhcNMTYwNzI4MTA1NjE3WhcNMTkwNzI5MTA1
# NjE3WjCBhzELMAkGA1UEBhMCREUxDDAKBgNVBAgTA05SVzESMBAGA1UEBxMJUGFk
# ZXJib3JuMRkwFwYDVQQKExBOZXQgYXQgV29yayBHbWJIMRkwFwYDVQQDExBOZXQg
# YXQgV29yayBHbWJIMSAwHgYJKoZIhvcNAQkBFhFpbmZvQG5ldGF0d29yay5kZTCC
# ASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJWtx+QDzgovn6AmkJ8UCTNr
# xtFJbRCHKNkfev6k35mMkNlibsVnFxooABDKSvaB21nXojMz63g+KLUEN5S4JiX3
# FKq5h2XahwWHvar/r2HMK2uJZ76360ePhuSZTnkifsxvwNxByQ9ot2S1O40AyVU5
# xfEUsBh7vVADMbjqBVlXuNAfsfpfvgjoR0CsOfgKk0CEDZ1wP0bXIkrk021a7lAO
# Yq9kqVDFv8K8O5WYvNcvbtAg3QW5JEaFnM3TMaOOSaWZMmIo7lw3e+B8rqknwmcS
# 66W2E0uayJXKqh/SXfS/xCwO2EzBT9Q1x0XiFR1LlEHQ0T/tfenBUlefIxfDZnEC
# AwEAAaOCAaQwggGgMA4GA1UdDwEB/wQEAwIHgDCBlAYIKwYBBQUHAQEEgYcwgYQw
# SAYIKwYBBQUHMAKGPGh0dHA6Ly9zZWN1cmUuZ2xvYmFsc2lnbi5jb20vY2FjZXJ0
# L2dzY29kZXNpZ25zaGEyZzNvY3NwLmNydDA4BggrBgEFBQcwAYYsaHR0cDovL29j
# c3AyLmdsb2JhbHNpZ24uY29tL2dzY29kZXNpZ25zaGEyZzMwVgYDVR0gBE8wTTBB
# BgkrBgEEAaAyATIwNDAyBggrBgEFBQcCARYmaHR0cHM6Ly93d3cuZ2xvYmFsc2ln
# bi5jb20vcmVwb3NpdG9yeS8wCAYGZ4EMAQQBMAkGA1UdEwQCMAAwPwYDVR0fBDgw
# NjA0oDKgMIYuaHR0cDovL2NybC5nbG9iYWxzaWduLmNvbS9nc2NvZGVzaWduc2hh
# MmczLmNybDATBgNVHSUEDDAKBggrBgEFBQcDAzAdBgNVHQ4EFgQUZLedJVdZSZd5
# lwNJFEgIc8KbEFEwHwYDVR0jBBgwFoAUDzrnrJSRdC2WAnODrZwuST8ZqlQwDQYJ
# KoZIhvcNAQELBQADggEBADYcz/+SCP59icPJK5w50yiTcoxnOtoA21GZDpt4GGVf
# RQJDWCDJMkU62xwu5HzqwimbwmBykrAf5Log1fLbggI83zIE4sMjkUe/BnnHpHgK
# LYv+3eLEwglMw/6Gmlq9IqNSD8YmTncGZFoFhrCrgAZUkA6RiVxuZrx2wiluueBI
# vfGs+tRA+7Tgx6Ed9kBybnc+xbAiTCNIcSo9OkPZfc3Q9saMgjIehBMXHLgMdrhv
# N5HXv/r4+aZ6asgv3ggArHrS1Pxp0f60hooVK4bA4Ph1td6YZ5lf8HA4uMmHvOjQ
# iNS0UjXqu5Vs6leIRM3pBjuX45xL6ydUsMlLhZQfansxggILMIICBwIBATBqMFox
# CzAJBgNVBAYTAkJFMRkwFwYDVQQKExBHbG9iYWxTaWduIG52LXNhMTAwLgYDVQQD
# EydHbG9iYWxTaWduIENvZGVTaWduaW5nIENBIC0gU0hBMjU2IC0gRzMCDFH6/Cfo
# wsq+AMu2DTAJBgUrDgMCGgUAoHgwGAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZ
# BgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYB
# BAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQU4aXiF9zkST84xL/H8PEcKnd77B0wDQYJ
# KoZIhvcNAQEBBQAEggEAGeOgMgYokYja8+66krkVUJIHIkjKwu7QbKOdooW47Gwv
# iYinQtn7pKNJjr22IvKMCPrhOQ5Smj13kHzUOGI+1/IvJL35Ntzh7eDD5pWENjUG
# O7DRfVy6OzI9As9kTshi2K5KYZa+nDJpgOBDttgwMQ3BkCRwqQa/VOTBmpKf3Dmc
# N2J8dxTY9XWesQKcMGTJlbh5Akk2zwAPp7ahEk9M19lakjem7or1Fsf6aYsfXvKk
# d8SUtypqOshw7bNW67IDy9u26AgvGbUkYIDRbtOtV60FsaTBSfoRtG5qWnEM7csj
# ss+8xKA8ayiUbOW21gRwk0v7DgyESqXVehjnBqftXw==
# SIG # End signature block
