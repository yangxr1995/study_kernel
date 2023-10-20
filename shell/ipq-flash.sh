#!/usr/bin/expect 

proc reboot_to_uboot {} {
	set timeout 60
	send "aa\n"
	expect {
		"root@" {
			send "reboot\n"
			sleep 10
			expect "U-Boot"
			send "\n"
			expect "Hit any key to stop autoboot"
			send "\n"
			return 0
		}
		"IPQ5018#" {
			send "reset\n"
			expect "U-Boot"
			send "\n"
			expect "Hit any key to stop autoboot"
			send "\n"
			return 0
		}
		timeout {
			puts "EXP ERROR : reboot_to_uboot timeout"
			return 1
		}
	}

}

proc check_net {ip ser} {
	set timeout 10
	send "\n"
	expect  "IPQ5018#"
	send "setenv ipaddr $ip\n"
	expect "IPQ5018#"
	send "setenv serverip $ser\n"
	expect "IPQ5018#"
	send "ping $ser\n"
	expect {
		"host $ser is alive" { 
			return 0 
		}
		"IPQ5018#" { 
			send "ping $ser\n"
			exp_continue
		}
		"host $ser is not alive" { 
			send "ping $ser\n" 
			exp_continue
		}
		timeout {
			return 1
		}
		default {
			puts "check_net err : currently not in uboot\n"
			sleep 1
		}
	}
}

proc do_flash {} {
	send "imgaddr=0x44000000 && source \$imgaddr:script\n"
	expect  {
		"Flashing wifi_fw_ipq5018_qcn9000_qcn6122" {
			send "\n"
			expect "IPQ5018#" {return 0}
		}
		"Wrong image format for" {return 1}
		"Unknown command" {return 1}
	}

}

proc do_tftp {} {
	set timeout 30
	send "tftpboot 0x44000000 nand-ipq5018-single.img\n"
	expect {
		"Bytes transferred" {
			return 0
		}
		"File not found" {
			return 1
		}
		timeout {
			return 1
		}
	}
}

proc flash_and_run_bootcmd {ip ser} {
	send "\n"
	expect  "IPQ5018#"
	send "setenv ipaddr $ip\n"
	expect "IPQ5018#"
	send "setenv serverip $ser\n"
	expect "IPQ5018#"
	check_net $ser

	send "\n"
	expect "IPQ5018#"

	send "tftpboot 0x44000000 nand-ipq5018-single.img\n"
	sleep 3
	expect {
		"##" {
			exp_continue}
		"Bytes transferred" {

			set flash_ret do_flash
			send "run bootcmd\n"
		}
	}
}

proc func {} {
	return 0
}


set timeout -1
set device "/dev/ttyUSB0"
set baudrate 115200
set ipaddr "192.168.2.1"
set serverip "192.168.2.2"

spawn minicom -D $device -b $baudrate
set ret [reboot_to_uboot]
if { $ret != 0 } {
	puts "\nfailed to reboot_to_uboot"
	exit 1
}
puts "\nreboot_to_uboot : ok"

sleep 4
set ret [check_net $ipaddr $serverip]
if { $ret != 0 } {
	puts "\nfailed to check_net ip : $ipaddr, server : $serverip"
	exit 1
}
puts "\ncheck_net : ok"


set ret [do_tftp]
if { $ret != 0 } {
	puts "\nfailed to do_tftp "
	exit 1
}
puts "\ndo_tftp : ok"


# expect if语句使用中括号，并且中括号不能和其他符号连接
sleep 1
set ret [do_flash]
if { $ret != 0 } {
	puts "\nfailed to do_flash "
	exit 1
}
puts "\ndo_flash : ok"

send "run bootcmd\n"
interact



# flash_and_run_bootcmd $ipaddr $serverip
# 
# interact
