# Switch-Configure.ps1 - Configure switch for StateTrace testing
$port = New-Object System.IO.Ports.SerialPort 'COM8', 9600, 'None', 8, 'One'
$port.DtrEnable = $true
$port.RtsEnable = $true
$port.ReadTimeout = 5000
$port.Open()

$CR = [char]13

function Send-Command {
    param([string]$cmd, [int]$wait = 1000)
    Write-Host ">>> $cmd" -ForegroundColor Yellow
    $port.Write("$cmd$CR")
    Start-Sleep -Milliseconds $wait
    $output = $port.ReadExisting()
    if ($output -and $output.Trim()) {
        Write-Host $output -ForegroundColor Gray
    }
    return $output
}

try {
    $null = $port.ReadExisting()
    Send-Command "terminal length 0" 500

    Write-Host "`n=== Entering Configuration Mode ===" -ForegroundColor Cyan
    Send-Command "configure terminal" 1000

    Write-Host "`n=== Basic Settings ===" -ForegroundColor Cyan
    Send-Command "hostname LAB-C9200L-AS-01" 500
    Send-Command "ip domain-name lab.local" 500
    Send-Command "no ip domain-lookup" 500

    Write-Host "`n=== Creating VLANs ===" -ForegroundColor Cyan
    Send-Command "vlan 10" 300
    Send-Command "name DATA" 300
    Send-Command "vlan 20" 300
    Send-Command "name VOICE" 300
    Send-Command "vlan 30" 300
    Send-Command "name MGMT" 300
    Send-Command "vlan 40" 300
    Send-Command "name SERVERS" 300
    Send-Command "vlan 50" 300
    Send-Command "name PRINTERS" 300
    Send-Command "vlan 99" 300
    Send-Command "name NATIVE" 300
    Send-Command "vlan 100" 300
    Send-Command "name GUEST" 300
    Send-Command "exit" 300

    Write-Host "`n=== Configuring Access Ports (Users) ===" -ForegroundColor Cyan
    Send-Command "interface range GigabitEthernet1/0/2-12" 500
    Send-Command "description User Access Port" 300
    Send-Command "switchport mode access" 300
    Send-Command "switchport access vlan 10" 300
    Send-Command "switchport voice vlan 20" 300
    Send-Command "spanning-tree portfast" 300
    Send-Command "spanning-tree bpduguard enable" 300
    Send-Command "exit" 300

    Write-Host "`n=== Configuring Server Ports ===" -ForegroundColor Cyan
    Send-Command "interface range GigabitEthernet1/0/13-16" 500
    Send-Command "description Server Port" 300
    Send-Command "switchport mode access" 300
    Send-Command "switchport access vlan 40" 300
    Send-Command "spanning-tree portfast" 300
    Send-Command "exit" 300

    Write-Host "`n=== Configuring Printer Ports ===" -ForegroundColor Cyan
    Send-Command "interface range GigabitEthernet1/0/17-20" 500
    Send-Command "description Printer Port" 300
    Send-Command "switchport mode access" 300
    Send-Command "switchport access vlan 50" 300
    Send-Command "spanning-tree portfast" 300
    Send-Command "exit" 300

    Write-Host "`n=== Configuring Guest Ports ===" -ForegroundColor Cyan
    Send-Command "interface range GigabitEthernet1/0/21-24" 500
    Send-Command "description Guest Wireless AP" 300
    Send-Command "switchport mode access" 300
    Send-Command "switchport access vlan 100" 300
    Send-Command "spanning-tree portfast" 300
    Send-Command "exit" 300

    Write-Host "`n=== Configuring Disabled/Reserved Ports ===" -ForegroundColor Cyan
    Send-Command "interface range GigabitEthernet1/0/25-36" 500
    Send-Command "description RESERVED - Disabled" 300
    Send-Command "switchport mode access" 300
    Send-Command "switchport access vlan 999" 300
    Send-Command "shutdown" 300
    Send-Command "exit" 300

    Write-Host "`n=== Configuring Uplink Trunks ===" -ForegroundColor Cyan
    Send-Command "interface TenGigabitEthernet1/0/37" 500
    Send-Command "description Uplink to CORE-SW-01" 300
    Send-Command "switchport mode trunk" 300
    Send-Command "switchport trunk native vlan 99" 300
    Send-Command "switchport trunk allowed vlan 10,20,30,40,50,99,100" 300
    Send-Command "exit" 300

    Send-Command "interface TenGigabitEthernet1/0/38" 500
    Send-Command "description Uplink to CORE-SW-02" 300
    Send-Command "switchport mode trunk" 300
    Send-Command "switchport trunk native vlan 99" 300
    Send-Command "switchport trunk allowed vlan 10,20,30,40,50,99,100" 300
    Send-Command "exit" 300

    Write-Host "`n=== Configuring SVIs ===" -ForegroundColor Cyan
    Send-Command "interface Vlan30" 500
    Send-Command "description Management VLAN" 300
    Send-Command "ip address 10.30.1.10 255.255.255.0" 300
    Send-Command "no shutdown" 300
    Send-Command "exit" 300

    Send-Command "ip default-gateway 10.30.1.1" 500

    Write-Host "`n=== Spanning-Tree Settings ===" -ForegroundColor Cyan
    Send-Command "spanning-tree mode rapid-pvst" 500
    Send-Command "spanning-tree vlan 1-100 priority 32768" 500

    Write-Host "`n=== Exit Config Mode ===" -ForegroundColor Cyan
    Send-Command "end" 500

    Write-Host "`n=== Configuration Complete ===" -ForegroundColor Green
}
finally {
    $port.Close()
}
