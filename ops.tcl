# ops.tcl
# irc channel operator script

source "[file dirname [info script]]/util.tcl"

package require util

namespace eval ::ops {

namespace import ::util::*

variable adminFlag       "|V"          ;# user flag for allowing op commands
variable pollFlag        "P"           ;# user flag for allowing poll op commands
variable putCommand      putnow        ;# send function: putnow, putquick, putserv, puthelp
variable debugLogLevel   8             ;# log all output to this log level [1-8, 0 = disabled]
variable channel         "#wims-test"  ;# name of the channel
variable scriptVersion   "0.2.4"       ;# script version
variable banPrefix       "-**"         ;# prefix so for separating bans set with .ban and other bans
variable banTime         1440          ;# number of minutes a ban should stay active
variable ns [namespace current]



proc send {unick dest text} {
	variable putCommand
	variable debugLogLevel
	if {$dest != ""} {
		if {$unick == $dest} {
			set put putMessage
		} else {
			set put putNotice
		}
		return [$put $unick $dest $text $putCommand $debugLogLevel]
	}
	return 0
}

proc topic {unick host handle dest text} {
	variable channel
	set op [finduser "*!$host"]
	if {![onchan $unick $channel]} { return 0 }
	if {![botisop $channel]} {
		send $unick $dest "I need to be op'd on the channel to change the topic"
		return 1
	}
	if {$text==""} {
		send $unick $dest "Usage: .topic <topic you want>"
		return 1
	}
	putserv "TOPIC $channel :$text"
	putlog "$op has changed the topic in $channel to $text"
}
mbind {msg pub} "$adminFlag$pollFlag"  {.topic} ${ns}::topic

proc kick {unick host handle dest text} {
	variable channel
	if {![onchan $unick $channel]} { return 0 }
	set op [finduser "*!$host"]
	global botnick
	set who [lindex $text 0]
	set why [lrange $text 1 end]
	if {$who==""} {
		send $unick $dest "Usage: .kick <nick> \[reason\]"
		return 1
	}
	if {![onchan $who $channel]} {
		send $unick $dest "$who isn't in $channel"
	}
	if {[string equal -nocase $who $botnick]} {
		send $unick $dest "You are not allowed to kick the bot"
		putlog "$op tried to kick the bot"
		return 1
	}
	if {[matchattr $who |+v $channel] || [matchattr $who |+o $channel] || [matchattr $who |+V $channel]} {
		send $unick $dest "You are not authorized to kick $who from $channel"
		putlog "$op tried to kick $who from $channel"
		return 1
	}
	putkick $channel $who $why
	putlog "$op has kicked $who from $channel for reason: ($why)"
}
mbind {msg pub} $adminFlag {.kick .k} ${ns}::kick

proc ban {unick host handle dest text} {
	variable channel
	variable banPrefix
	variable banTime
	if {![onchan $unick $channel]} { return 0 }
	set op [finduser "*!$host"]
	set who [lindex $text 0]
	set reason [lrange $text 1 end]
	if {$who==""} {
		send $unick $dest "Usage: .ban <nick|hostmask> \[reason\]"
		return 1
	}
	if {[matchattr $who |+v $channel] || [matchattr $who |+o $channel] || [matchattr $who |+V $channel]} {
		send $unick $dest "You are not authorized to ban $who from $channel"
		putlog "$op tried to ban $who from $channel"
		return 1
	}
	if {[string match *!*@* $who]} { ;# Ban by hostmask
		if {[string trim $reason] != ""} {
			set nick [lindex $reason 0]
			set reason [lrange $reason 1 end]
			if {[string trim $reason] != ""} { append nick " ($reason)" }
			set reason "$banPrefix $nick"
		} else {set reason "$banPrefix"}
		newchanban $channel $who $op $reason $banTime
		putlog "$op banned $who from $channel ($reason)"
	} { ;# Ban by nickname
		set hostmask [lindex [split [getchanhost $who] @] 1]
		if {$hostmask!=""} {
			set who "$banPrefix $who"
			if {[string trim $reason] != ""} {append who " ($reason)"}
			newchanban $channel "*!*@$hostmask" $op $who $banTime
			putlog "$op banned $who (*!*@$hostmask) from $channel"
		}
	}
}
mbind {msg pub} $adminFlag {.ban .b .kban .kickban .kb} ${ns}::ban

proc unBan {unick host handle dest mask} {
	variable channel
	if {![onchan $unick $channel]} { return 0 }
	set op [finduser "*!$host"]
	variable banPrefix
	if {$mask==""} {
		send $unick $dest "Usage: .unban <hostmask>"
		return 1
	}
	set removedBan 0
	if {![string match *!*@* $mask]} {  ;# Unban by nickname
		set bans [banlist $channel]
		set count 0
		foreach {ban} $bans {
			set hostmask [lindex $ban 0]
			set comment [lindex $ban 1]
			set prefix [lindex $comment 0]
			set who [lrange $comment 1 end]
			if {[llength $who]>=1} {
				set who [lindex $who 0]
			}
			if {[string equal -nocase $who $mask] && [string equal -nocase $prefix $banPrefix]} { ;# Only unban bans set by .ban
				if {[killchanban $channel $hostmask]} { 
					set removedBan 1
					incr count
				}
			}
		}
		if {!$count} {
			send $unick $dest "Nickname $mask not found in banlist"
			return 1
		} else {
			send $unick $dest "Removed $count ban[s $count] matching $mask on $channel"
		}
	} else { ;# Unban by hostmask
		set bans [banlist $channel]
		foreach {ban} $bans {
			set hostmask [lindex $ban 0]
			set comment [lindex $ban 1]
			set prefix [lindex $comment 0]
			if {[string equal -nocase $hostmask $mask] && [string equal -nocase $prefix $banPrefix]} { ;# Only unban bans set by .ban
				if {[killchanban $channel [lindex $mask 0]]} { set removedBan 1}
			}
		}
	}
	if {$removedBan} { putlog "$op unbanned [lindex $mask 0] on $channel"}
}
mbind {msg pub} $adminFlag {.unban .ub} ${ns}::unBan

proc listBans {unick host handle dest text} {
	variable channel
	variable banPrefix
	set op [finduser "*!$host"]
	set bans [banlist $channel]
	set totalBans 0
	foreach {ban} $bans {
		set comment [lindex $ban 1]
		set prefix [lindex $comment 0]
		if {$prefix==$banPrefix} {incr totalBans}
	}
	if {$totalBans==0} {
		send $unick $dest "There are no bans in $channel"
		return 1
	} else {
		send $unick $dest "There are a total of $totalBans ban[s $totalBans] in $channel :"
	}
	set count 0
	foreach {ban} $bans {
		set hostmask [lindex $ban 0]
		set comment [lindex $ban 1]
		set prefix [lindex $comment 0]
		set who [lrange $comment 1 end]
		set reason "No Reason"
		if {[llength $who]>=1} {
			set reason [lrange $who 1 end]
			set who [lindex $who 0]
		}
		set expires [clock format [lindex $ban 2]]
		set added [clock format [lindex $ban 3]]
		set op [lindex $ban 5]
		if {$prefix == $banPrefix} {
			incr count
			send $unick $dest [format "%-4d: %-10s %-60s , set by $op at $added" $count $who $hostmask] 
		}
	}
}
mbind {msg pub} $adminFlag {.listbans .lb} ${ns}::listBans

proc help {unick host handle dest text} {
	variable channel
	variable scriptVersion
	variable adminFlag
	set output ""
	if {![onchan $unick $channel]} { return 0 }
	send $unick $dest "[b][u]$channel OPERATOR SCRIPT v$scriptVersion:[/u][/b]"
	if {[matchattr $handle $adminFlag $channel]} {
		set output [concat {
			{ Operator commands on this bot }
			{  .topic <topic> .................. Sets the topic in the channel it's typed}
			{  .kick <nick> [reason] ........... Kick a user from the channel}
			{  .kban <nick> [reason] ........... Kick and ban a user from the channel}
			{  .ban <nick|hostmask> [reason] ... Ban a user by nickname or hostmask}
			{    It's recommended to specify the nickname of the banned hostmask as reason when using .ban <hostmask> <reason> }
			{  .unban <nick|hostmask> .......... Unban a nickname or hostmask}
			{  .listbans ....................... Displays the banlist}
			{  .ohelp .......................... Displays this help menu}
			{}
		}]
	} else {
		set output [concat {
			{ Poll Operator commands on this bot }
			{  .topic <topic> .................. Sets the topic in the channel it's typed}
			{  .ohelp .......................... Displays this help menu}
			{}
		}]
	}
	foreach line $output {
			send $unick $dest $line
	}
}
mbind {msg pub} "$adminFlag$pollFlag" {.ohelp} ${ns}::help

proc rules {unick host handle dest text} {
	variable channel
	if {![onchan $unick $channel]} { return 0 }

	variable adminFlag
	variable scriptVersion
	variable channel

	send $unick $dest "[b][u]#MMA-TV CHANNEL RULES:[/u][/b]"

	foreach {line} [concat {
		{  You will be banned for 24 hours with no warning for any of the following:}
		{    * Posting child pornography}
		{    * Blatant/Obscene racism}
		{    * Posting graphic brutality, homosexual media, or anything vile}
		{    * Exploits to crash users (DCC or other)}
		{    * Posting links with the intent to infect another user (trojan/hijack)}
		{    * Repeating more than 3 similar lines (3 minute ban only) -- channel is noisy enough as is}
		{  You will be warned for any of the following (msg or kick):}
		{    * Trolling (continually fueling arguments for the sake of arguing)}
		{    * Spamming/Advertising}
		{    * Spoiling unaired fight results until channel ops or regulars say it's ok (ask if unsure).}
		{    * Bringing unauthorized keyword triggers, bots or botnets to the channel}
		{    * 'thanks for voice/op' or 'now playing' scripts}
		{    * Begging for op/voice status}
		{    * Using bold or colored text}
		{}
	}] {	send $unick $dest $line
	}
	if {[matchattr $handle $adminFlag $channel]} {
		send $unick $dest "[b][u]#MMA-TV CHANNEL OPERATOR RULES:[/b][/u]"
		foreach {line} [concat {
			{    * Do not kick or ban another channel operator. Talk to Sang if their status needs to be changed}
			{    * Do not kick or ban users without a rule violation (personal insults do not count as violation)}
			{    * Do not abuse the topic (no quotes or bashing users)}
			{    * Enforce the rules fairly, not just for the people you don't like}
			{    * Warn for rule violations with a kick before a ban}
			{    * Type .ohelp for channel operator commands}
			{}
		}] {
			send $unick $dest $line
		}
	}
	return 1
}
mbind {msg pub} - {.rules} ${ns}::rules


putlog "[b]Operator script TCL $scriptVersion loaded[/b]"

}