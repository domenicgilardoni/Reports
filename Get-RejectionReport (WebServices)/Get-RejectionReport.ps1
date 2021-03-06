param (
	[Parameter(Mandatory=$false)][int] $NumberOfDaysToReport = 7,
	[Parameter(Mandatory=$true)][string] $SMTPHost,
	[Parameter(Mandatory=$false)][string] $ReportSender = "NoSpamProxy Report Sender <nospamproxy@example.com>",
	[Parameter(Mandatory=$true)][string] $ReportRecipient,
	[Parameter(Mandatory=$false)][string] $ReportSubject = "Auswertung",
	[Parameter(Mandatory=$false)][int] $TopAddressesCount = 5,
	[Parameter(Mandatory=$false)][string[]] $excludeFromTopAddresses = @()
)

$reportFileName = [System.IO.Path]::Combine($Env:TEMP, "reject-analysis.html")
$totalRejected = 0
$tempRejected = 0
$permanentRejected = 0
$reputationRejected = 0
$rblRejected = 0
$cyrenSpamRejected = 0
$cyrenAVRejected = 0
$cyrenIPRepRejected = 0
$surblRejected = 0
$characterSetRejected = 0
$wordRejected = 0
$contentrejected = 0
$greylistrejected = 0
$rdnsPermanentRejected = 0
$decryptPolicyRejected = 0
$onBodyRejected = 0
$onEnvelopeRejected = 0
$dateStart = (Get-Date).AddDays(-$NumberOfDaysToReport)
$dateStop = Get-Date
$dateTo = Get-Date -format "dd.MM.yyyy"
$dateFrom = $dateStart.ToString("dd.MM.yyyy")
$topSpammers = @{}

Write-Host "Getting MessageTracks from NoSpamProxy for..."
Write-Host "`tTemporarily Blocked"
$messageTracks = Get-NSPMessageTrack -From $dateStart -Status TemporarilyBlocked -Directions FromExternal -WithActions -WithDeliveryAttempts -WithFilters -WithOperations -WithAddresses

$totalRejected += $messageTracks.Count
$tempRejected += $messageTracks.Count

foreach ($item in $messageTracks)
{
    $sender = ($item.Addresses|?{[string]$_.AddressType -eq "Sender"}).Address
    if($sender -ne $null) {
        $topSpammers[$sender]++
    }
	foreach ($action in $item.Actions){
		if ($action.Name -eq "greylisting" -and $action.Decision -notcontains "Pass")
		{
		    $onEnvelopeRejected++
	 	    $greylistrejected++
		}
	}
}

Write-Host "`tPermanently Blocked"
$messageTracks = Get-NSPMessageTrack -From $dateStart -Status PermanentlyBlocked -Directions FromExternal -WithActions -WithDeliveryAttempts -WithFilters -WithOperations -WithAddresses

$totalRejected += $messageTracks.Count
$permanentRejected += $messageTracks.Count

foreach ($item in $messageTracks)
{
    $sender = ($item.Addresses|?{[string]$_.AddressType -eq "Sender"}).Address
    if($sender -ne $null) {
        $topSpammers[$sender]++
    }
	foreach ($permanentvalidationentry in $item.Filters)
	{
		if ($permanentvalidationentry.Name -eq "realtimeBlocklist" -and $permanentvalidationentry.Scl -gt 0)
		{
			$rblRejected++
			$onEnvelopeRejected++
		}

		if ($permanentvalidationentry.Name -eq "surblFilter" -and $permanentvalidationentry.Scl -gt 0)
		{
			$surblRejected++
			$onBodyRejected++
		}

		if ($permanentvalidationentry.Name -eq "cyrenFilter" -and $permanentvalidationentry.Scl -gt 0)
		{
			$cyrenSpamRejected++
			$onBodyRejected++
		}

		if ($permanentvalidationentry.Name -eq "characterSetFilter" -and $permanentvalidationentry.Scl -gt 0)
		{
			$characterSetRejected++
			$onBodyRejected++
		}

		if ($permanentvalidationentry.Name -eq "wordFilter" -and $permanentvalidationentry.Scl -gt 0)
		{
			$wordRejected++
			$onBodyRejected++
		}

		if (($permanentvalidationentry.Name -eq "validateSignatureAndDecrypt") -and ($permanentvalidationentry.Decision -notcontains "Pass" ))
		{
			$decryptPolicyRejected++
			$onBodyRejected++
		}
	    
        if (($permanentvalidationentry.Name -eq "reputation") -and ($permanentvalidationentry.Scl -gt 0 ))
		{
			$reputationRejected++
			$onEnvelopeRejected++
		}
		if (($permanentvalidationentry.Name -eq "cyrenIpReputationFilter") -and ($permanentvalidationentry.Scl -gt 0 ))
		{
			$cyrenIPRepRejected++
			$onEnvelopeRejected++
		}
		
	}

    foreach ($action in $item.Actions)
    {
    	if ($action.Name -eq "cyrenAction" -and $action.Decision -notcontains "Pass")
		{
			$cyrenAVRejected++
			$onBodyRejected++
		}
		if ($action.Name -eq "ContentFiltering" -and $action.Decision -notcontains "Pass")
		{
		    $onBodyRejected++
	 	    $contentrejected++
		}
    }
}
Write-Host "Evaluating top spammers"
$topSpammers = $topSpammers.GetEnumerator() | ?{$_.Name -notin $excludeFromTopAddresses} | sort Value -Descending | select -First $TopAddressesCount


$ownedDomains = (Get-NspOwnedDomain).Domain

Write-Host "Evaluating top Senders/Recipients Outgoing"
$messageTracks = (Get-NSPMessageTrack -From $dateStart -Directions FromLocal -Status Success -WithAddresses|?{($_.Addresses|?{[string]$_.AddressType -eq "Recipient" -and $_.Domain -in $ownedDomains}) -eq $null})

$outboundmessages = $messageTracks.Count
$topLocal = @{}
$topLocal["Sender"] = @{}
$topLocal["Recipient"] = @{}

foreach ($addr in ($messageTracks.Addresses)) {
    $topLocal[[string]$addr.AddressType][$addr.Address]++
}

$topRecipientsOutgoing = ($topLocal["Recipient"].GetEnumerator() | ?{$_.Name -notin $excludeFromTopAddresses} | Sort Value -Descending | select -First $TopAddressesCount)
$topSendersOutgoing = ($topLocal["Sender"].GetEnumerator() | ?{$_.Name -notin $excludeFromTopAddresses} | Sort Value -Descending | select -First $TopAddressesCount)



Write-Host "Evaluating top Senders/Recipients Incoming"
$messageTracks = Get-NSPMessageTrack -From $dateStart -Directions FromExternal -Status Success -WithAddresses

$inboundmessages = $messageTracks.Count
$topExternal = @{}
$topExternal["Sender"] = @{}
$topExternal["Recipient"] = @{}

foreach ($addr in $messageTracks.Addresses) {
    $topExternal[[string]$addr.AddressType][$addr.Address]++
}

$topRecipientsIncoming = ($topExternal["Recipient"].GetEnumerator() | ?{$_.Name -notin $excludeFromTopAddresses} | Sort Value -Descending | select -First $TopAddressesCount)
$topSendersIncoming = ($topExternal["Sender"].GetEnumerator() | ?{$_.Name -notin $excludeFromTopAddresses} | Sort Value -Descending | select -First $TopAddressesCount)



$mailsprocessed = $outboundmessages+$inboundmessages

if ($inboundmessages -eq 0) {
    $blockedpercentage = 0
} else {
    $blockedpercentage = [Math]::Round($totalRejected/$inboundmessages*100,2)
}

if ($totalRejected -eq 0) {
    $cyrenspamblockpercentage = 0
    $cyrenavblockpercentage = 0
    $surblblockedpercentage = 0
    $charactersetblockedpercentage = 0
    $wordrejectedblockedpercentage = 0
    $decryptpolicyblockedpercentage = 0
    $rblRejectedpercentage = 0
    $contentrejectedpercentage = 0
    $greylistrejectedpercentage = 0
    $reputationRejectedpercentage = 0
    $cyreniprepRejectedpercentage = 0
} else {
    $cyrenspamblockpercentage = [Math]::Round($cyrenSpamRejected/$totalRejected*100,2)
    $cyrenavblockpercentage = [Math]::Round($cyrenAVRejected/$totalRejected*100,2)
    $surblblockedpercentage = [Math]::Round($surblRejected/$totalRejected*100,2)
    $charactersetblockedpercentage = [Math]::Round($characterSetRejected/$totalRejected*100,2)
    $wordrejectedblockedpercentage = [Math]::Round($wordRejected/$totalRejected*100,2)
    $decryptpolicyblockedpercentage = [Math]::Round($decryptPolicyRejected/$totalRejected*100,2)
    $rblRejectedpercentage = [Math]::Round($rblRejected/$totalRejected*100,2)
    $contentrejectedpercentage = [Math]::Round($contentRejected/$totalRejected*100,2)
    $greylistrejectedpercentage = [Math]::Round($greylistRejected/$totalRejected*100,2)
    $reputationRejectedpercentage = [Math]::Round($reputationRejected/$totalRejected*100,2)
    $cyreniprepRejectedpercentage = [Math]::Round($cyrenIPRepRejected/$totalRejected*100,2)
}

Write-Host " "
Write-Host "TemporaryReject Total:" $tempRejected
Write-Host "PermanentReject Total:" $permanentRejected
Write-Host "TotalReject:" $totalRejected
Write-Host "Generating Report..."


$global:htmlout = "<html>
		<head>
			<title>Auswertung der abgewiesenen E-Mails</title>
			<style>
                table {border-spacing: 0px; border: 1px solid black; background-color: #3867d6; float:left; margin:10px}

                th {padding: 10px; color: white;}
      			td {padding: 6px 10px; color: white;}

                tr.newsegment>td,tr.newsegment>th {border-top-color: black; border-top-width: 1px; border-top-style: solid;}

                tr.sub>td {background-color: #4b7bec;}
                tr.sub>td:first-of-type {border-left-color: #3867d6;border-left-style:solid;border-left-width:8px}
                
    		</style>
		</head>
	<body style=font-family:arial>
		<table>
			<tr><th>"+ $dateFrom +" bis "+ $dateTo +" ("+$NumberOfDaysToReport+" Tage)</th><th>Count</th><th>Percent</th></tr>
			<tr><td>Mails Processed</td><td>" + $mailsprocessed +"</td><td>&nbsp;</td></tr>
            <tr class=`"sub`"><td>Sent</td><td>" + $outboundmessages +"</td><td>&nbsp;</td></tr>
			<tr class=`"sub`"><td>Received</td><td>" + $inboundmessages +"</td><td>&nbsp;</td></tr>

			<tr class=`"newsegment`"><td>Mails blocked</td><td>" + $totalRejected +"</td><td>" + $blockedpercentage +" %</td></tr>
			<tr class=`"sub`"><td>Realtime Blocklist Check</td><td>" + $rblRejected +"</td><td>" + $rblRejectedpercentage +" %</td></tr>
			<tr class=`"sub`"><td>Reputation Check</td><td>" + $reputationRejected +"</td><td>" + $reputationRejectedpercentage +" %</td></tr>
			<tr class=`"sub`"><td>Cyren AntiSpam</td><td>" + $cyrenSpamRejected +"</td><td>" + $cyrenspamblockpercentage +" %</td></tr>
			<tr class=`"sub`"><td>Cyren Premium AntiVirus</td><td>" + $cyrenAVRejected +"</td><td>" + $cyrenavblockpercentage +" %</td></tr>
			<tr class=`"sub`"><td>Cyren IP Reputation</td><td>" + $cyrenIPRepRejected +"</td><td>" + $cyreniprepRejectedpercentage +" %</td></tr>
			<tr class=`"sub`"><td>Spam URI Realtime Blocklists</td><td>" + $surblRejected +"</td><td>" + $surblblockedpercentage +" %</td></tr>
			<tr class=`"sub`"><td>Allowed Unicode Character Sets</td><td>" + $characterSetRejected +"</td><td>" + $charactersetblockedpercentage +" %</td></tr>
			<tr class=`"sub`"><td>Word Matching</td><td>" + $wordRejected +"</td><td>" + $wordrejectedblockedpercentage +" %</td></tr>
			<tr class=`"sub`"><td>DecryptPolicy Reject</td><td>" + $decryptPolicyRejected +"</td><td>" + $decryptpolicyblockedpercentage +" %</td></tr>
			<tr class=`"sub`"><td>ContentFiltering</td><td>" + $contentrejected + "</td><td>" + $contentrejectedpercentage + " %</td></tr>
			<tr class=`"sub`"><td>Greylisting</td><td>" + $greylistrejected + "</td><td>" + $greylistrejectedpercentage + " %</td></tr>
        </table>"


function enumerateAddressList($addrlist) {
    foreach($addr in $addrlist) {
        $global:htmlout += "<tr class=`"sub`"><td>" + $addr.Key + "</td><td>" + $addr.Value + "</td><td>&nbsp;</td></tr>"
    }
}

$global:htmlout += "<table>
            <tr><th>Top Local E-Mail Addresses</th><th>Count</th><td>&nbsp;</td></tr>
            <tr><td>Most E-Mails From</td><td>&nbsp;</td><td>&nbsp;</td></tr>"
enumerateAddressList($topSendersOutgoing)
$global:htmlout += "<tr class=`"newsegment`"><td>Most E-Mails To</td><td>&nbsp;</td><td>&nbsp;</td></tr>"
enumerateAddressList($topRecipientsIncoming)
$global:htmlout += "</table>"



$global:htmlout += "<table>
            <tr><th>Top External E-Mail Addresses</th><th>Count</th><td>&nbsp;</td></tr>
            <tr><td>Most E-Mails From</td><td>&nbsp;</td><td>&nbsp;</td></tr>"
enumerateAddressList($topSendersIncoming)
$global:htmlout += "<tr class=`"newsegment`"><td>Most E-Mails To</td><td>&nbsp;</td><td>&nbsp;</td></tr>"
enumerateAddressList($topRecipientsOutgoing)
$global:htmlout += "<tr class=`"newsegment`"><td>Top Spammers</td><td>&nbsp;</td><td>&nbsp;</td></tr>"
enumerateAddressList($topSpammers)
$global:htmlout += "</table>"

$global:htmlout | Out-File $reportFileName

Write-Host "Report Generated Successfully"

"Sending report to $ReportRecipient"
Send-MailMessage -SmtpServer $SmtpHost -From $ReportSender -To $ReportRecipient -Subject $ReportSubject -Body "Im Anhang dieser E-Mail finden Sie den Bericht mit der Auswertung der abgewiesenen E-Mails." -Attachments $reportFileName
Write-Host "Doing some cleanup.."
Remove-Item $reportFileName
Write-Host "Done."
# SIG # Begin signature block
# MIIMSwYJKoZIhvcNAQcCoIIMPDCCDDgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU2oJv2lCYS6RMQftOXY3nIsC4
# OnqgggmqMIIElDCCA3ygAwIBAgIOSBtqBybS6D8mAtSCWs0wDQYJKoZIhvcNAQEL
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
# BAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUSUs7TuMBX9BZTtJIyKHuLKnmuNQwDQYJ
# KoZIhvcNAQEBBQAEggEAGoaEslExG83j/aXghkeMBzmeYX0nBVEtrlOHvnjSAKim
# mCq3wO/ylyRwInIBXA2Ev0YuTT4QfUQEmSj3ug1xEHwZROgeL0FHtkOby+GBFJJB
# 1kNuckdlpe8HzBtPk1hxBbfZkV5pO7UfT/86E0xNVs9xTo21Bu0AhQYyUhUu/2ip
# 3shZcIZGL2fDu8v/wCIuLJ6lUikAss3uk/mHlt/kn/q5PnxOW5SfbSyB/111yhbp
# V7bYb3v41+o7v0Yhe8cwtNNoqlALhpQqDQVLpdYzeKwh5uTGgX5Wht9UObv/WWym
# UpEhbfZsDOw2+qPuh0POdONkpPujvTDFx9YrDNdhPA==
# SIG # End signature block
