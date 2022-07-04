#!/bin/bash

## @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
## vpn_module: vpn scripts for a polybar, setup stock for Mullvad VPN
## 	by Shervin S. (shervin@tuta.io)

## 	vpn_module reports your VPN's status as [<ip_address> | connecting... | No VPN ].
##  With optional dependencies, <ip_address> will be replaced with <city> <country>.
##  You can also connect and disconnect via left-clicks, or with rofi, right-click to
##  access a menu and select between your favorite locations, set in VPN_LOCATIONS,
##  as well as 35 countries covered by Mullvad VPN.

##	dependencies (assuming use with Mullvad VPN):
##		mullvad-vpn (or mullvad-vpn-cli)

##	optional dependencies:
##		rofi 				  - allows menu-based control of mullvad
##		geoip, geoip-database - provide country instead of public ip address
## 		geoip-database-extra  - also provides city info
##      xclip                 - allows copying ip address to clipboard

## polybar setup:
## - Append contents of vpn_user_module file to user_modules.ini
## - Add "vpn" module to your config.ini under modules


## @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
## User Settings

## [Set VPN commands]. Setup for Mullvad is done below.
# The first three commands should have direct equivalents for most VPNs.
# The relay_set command assumes <country_code> <city_code> will follow as arguments. See below.
VPN_CONNECT="nordvpn connect"
VPN_DISCONNECT="nordvpn disconnect"
VPN_GET_STATUS="nordvpn status"
VPN_RELAY_SET_LOCATION="nordvpn d; nordvpn c"

## [Set VPN status parsing]
# The first command cuts the status, which is compared to keywords below.
# Note from Julia: this should cover most VPNs, if it's missing something let me know
VPN_STATUS="$($VPN_GET_STATUS | grep -Eio 'connected|connecting|disconnected' \
	| tr '[:upper:]' '[:lower:]')"
CONNECTED="connected"
CONNECTING="connecting"

## [Set colors] (set each variable to nothing for default color)
ICON_CONNECTED=""
ICON_CONNECTING="ﱱ"
ICON_DISCONNECTED=""
COLOR_CONNECTED="#a5fb8f"
COLOR_CONNECTING="#FAE3B0"
COLOR_DISCONNECTED="#f087bd"

## [Set 8 favorite VPN locations]
# These are passed to your VPN as `$VPNCOMMAND_RELAY_SET_LOCATION <input>`.
VPN_LOCATIONS=("United_States Denver" "United_States Chicago" "United_States New_York" "United_States" "Japan" "Australia" "France" "Brazil")

## [Set optional rofi menu style]. `man rofi` for help on location params.
icon_connect="⇋"
icon_fav="•"
icon_country="⚑"
rofi_location="-location 3 -xoffset -530 -yoffset +30"
rofi_menu_name="ﱾ VPN"


## @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
## Main Script

# Country codes, taken from `mullvad relay list`.
# They ought to connect to your VPN's choice of server in the region.
COUNTRIES=("Albania (al)" "Argentina (ar)" "Australia (au)" "Austria (at)" "Belgium (be)" "Bosnia & Herzegovina (bih)" "Brazil (br)" "Bulgaria (bg)" "Canada (ca)" "Chile (cl)" "Costa Rica (cr)" "Croatia (hr)" "Cyprus (cy)" "Czech Republic (cz)" "Denmark (dk)" "Estonia (ee)" "Finland (fi)" "France (fr)" "Georgia (ge)" "Germany (de)" "Greece (gr)" "Hong Kong (hk)" "Hungary (hu)" "Iceland (is)" "Ireland (ie)" "Israel (il)" "Italy (it)" "Japan (jp)" "Latvia (lv)" "Lithuania (lt)" "Luxembourg (lu)" "Malaysia (my)" "Mexico (mx)" "Moldova (md)" "Netherlands (nl)" "New Zealand (nz)" "North Macedonia (mk)" "Norway (no)" "Poland (pl)" "Portugal (pt)" "Romania (ro)" "Serbia (rs)" "Singapore (sg)" "Slovakia (sk)" "Slovenia (si)" "South Africa (sa)" "South Korea (kr)" "Spain (es)" "Sweden (se)" "Switzerland (ch)" "Taiwan (tw)" "Thailand (th)" "Turkey (tr)" "Ukraine (ua)" "United Kingdom (gb)" "United States (us)" "Vietnam (vn)")
COUNTRY_CODES=("Albania" "Argentina" "Australia" "Austria" "Belgium" "Bosnia_And_Herzegovina" "Brazil" "Bulgaria" "Canada" "Chile" "Costa_Rica" "Croatia" "Cyprus" "Czech_Republic" "Denmark" "Estonia" "Finland" "France" "Georgia" "Germany" "Greece" "Hong_Kong" "Hungary" "Iceland" "Ireland" "Israel" "Italy" "Japan" "Latvia" "Lithuania" "Luxembourg" "Malaysia" "Mexico" "Moldova" "Netherlands" "New_Zealand" "North_Macedonia" "Norway" "Poland" "Portugal" "Romania" "Serbia" "Singapore" "Slovakia" "Slovenia" "South_Africa" "Sout_Korea" "Spain" "Sweden" "Switzerland" "Taiwan" "Thailand" "Turkey" "Ukraine" "United_Kingdom" "United_States" "Vietnam")

# Concatenate favorite and country arrays
VPN_CODES=("${VPN_LOCATIONS[@]}")
VPN_CODES+=("${COUNTRY_CODES[@]}")
VPN_LOCATIONS+=("${COUNTRIES[@]}")


ip_address_lookup() {
	ip_address=$($VPN_GET_STATUS | \
		awk 'match($0,/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/){print substr($0,RSTART,RLENGTH)}')
	if [ -z "$ip_address" ]; then
		ip_address=$(curl --silent https://ipaddr.pub)
	fi
	echo "$ip_address"
}


vpn_report() {
# continually reports connection status
	if [ "$VPN_STATUS" = "$CONNECTED"  ]; then
		if [ "$@" ] && [ "$1" == "--no-geoip" ]; then
			country=$($VPN_GET_STATUS | awk 'tolower ($0) ~ /country/{print $2}')
			city=$($VPN_GET_STATUS | awk 'tolower ($0) ~ /country/{print $2}')
			report="$city $country"
		elif hash geoiplookup 2>/dev/null; then
			ip_address=$(ip_address_lookup)
			country=$(geoiplookup "$ip_address" | head -n1 | cut -c24-25)
			city=$(geoiplookup "$ip_address" | cut -d',' -f5 | sed -n '2{p;q}' | sed 's/^ //')
			report="$city $country"
		else
			report=$(ip_address_lookup)
		fi
		echo "%{F$COLOR_CONNECTED}$ICON_CONNECTED $report%{F-}"
	elif [ "$VPN_STATUS" = "$CONNECTING" ]; then
		echo "%{F$COLOR_CONNECTING}$ICON_CONNECTING Connecting...%{F-}"
	else
		echo "%{F$COLOR_DISCONNECTED}$ICON_DISCONNECTED VPN Disconnected%{F-}"
	fi
}


vpn_toggle_connection() {
# connects or disconnects vpn
    if [ "$VPN_STATUS" = "$CONNECTED" ]; then
        $VPN_DISCONNECT
    else
        $VPN_CONNECT
    fi
}


vpn_location_menu() {
# Allows control of VPN via rofi menu. Selects from VPN_LOCATIONS.
	if hash rofi 2>/dev/null; then
		## shellcheck throws errors here, but the globbing is intentional
		# shellcheck disable=SC2086
		MENU="$(rofi $rofi_location -sep "|" -dmenu -i -p "$rofi_menu_name" <<< \
			" $icon_connect (dis)connect| $icon_fav ${VPN_LOCATIONS[0]}| $icon_fav ${VPN_LOCATIONS[1]}| $icon_fav ${VPN_LOCATIONS[2]}| $icon_fav ${VPN_LOCATIONS[3]}| $icon_fav ${VPN_LOCATIONS[4]}| $icon_fav ${VPN_LOCATIONS[5]}| $icon_fav ${VPN_LOCATIONS[6]}| $icon_fav ${VPN_LOCATIONS[7]}| $icon_country ${VPN_LOCATIONS[8]}| $icon_country ${VPN_LOCATIONS[9]}| $icon_country ${VPN_LOCATIONS[10]}| $icon_country ${VPN_LOCATIONS[11]}| $icon_country ${VPN_LOCATIONS[12]}| $icon_country ${VPN_LOCATIONS[13]}| $icon_country ${VPN_LOCATIONS[14]}| $icon_country ${VPN_LOCATIONS[15]}| $icon_country ${VPN_LOCATIONS[16]}| $icon_country ${VPN_LOCATIONS[17]}| $icon_country ${VPN_LOCATIONS[18]}| $icon_country ${VPN_LOCATIONS[19]}| $icon_country ${VPN_LOCATIONS[20]}| $icon_country ${VPN_LOCATIONS[21]}| $icon_country ${VPN_LOCATIONS[22]}| $icon_country ${VPN_LOCATIONS[23]}| $icon_country ${VPN_LOCATIONS[24]}| $icon_country ${VPN_LOCATIONS[25]}| $icon_country ${VPN_LOCATIONS[26]}| $icon_country ${VPN_LOCATIONS[27]}| $icon_country ${VPN_LOCATIONS[28]}| $icon_country ${VPN_LOCATIONS[29]}| $icon_country ${VPN_LOCATIONS[30]}| $icon_country ${VPN_LOCATIONS[31]}| $icon_country ${VPN_LOCATIONS[32]}| $icon_country ${VPN_LOCATIONS[33]}| $icon_country ${VPN_LOCATIONS[34]}| $icon_country ${VPN_LOCATIONS[35]}| $icon_country ${VPN_LOCATIONS[36]}| $icon_country ${VPN_LOCATIONS[37]}| $icon_country ${VPN_LOCATIONS[38]}| $icon_country ${VPN_LOCATIONS[39]}| $icon_country ${VPN_LOCATIONS[40]}| $icon_country ${VPN_LOCATIONS[41]}| $icon_country ${VPN_LOCATIONS[42]}| $icon_country ${VPN_LOCATIONS[43]}| $icon_country ${VPN_LOCATIONS[44]}| $icon_country ${VPN_LOCATIONS[45]}| $icon_country ${VPN_LOCATIONS[46]}| $icon_country ${VPN_LOCATIONS[47]}| $icon_country ${VPN_LOCATIONS[48]}| $icon_country ${VPN_LOCATIONS[49]}| $icon_country ${VPN_LOCATIONS[50]}| $icon_country ${VPN_LOCATIONS[51]}| $icon_country ${VPN_LOCATIONS[52]}| $icon_country ${VPN_LOCATIONS[53]}| $icon_country ${VPN_LOCATIONS[54]}| $icon_country ${VPN_LOCATIONS[55]}| $icon_country ${VPN_LOCATIONS[56]}| $icon_country ${VPN_LOCATIONS[57]}| $icon_country ${VPN_LOCATIONS[58]}| $icon_country ${VPN_LOCATIONS[59]}| $icon_country ${VPN_LOCATIONS[60]}| $icon_country ${VPN_LOCATIONS[61]}| $icon_country ${VPN_LOCATIONS[62]}| $icon_country ${VPN_LOCATIONS[63]}| $icon_country ${VPN_LOCATIONS[64]}")"

		# shellcheck disable=SC2086
	    case "$MENU" in
			*connect) vpn_toggle_connection; return;;
			*"${VPN_LOCATIONS[0]}") $VPN_RELAY_SET_LOCATION ${VPN_CODES[0]} ;;
			*"${VPN_LOCATIONS[1]}") $VPN_RELAY_SET_LOCATION ${VPN_CODES[1]} ;;
			*"${VPN_LOCATIONS[2]}") $VPN_RELAY_SET_LOCATION ${VPN_CODES[2]} ;;
			*"${VPN_LOCATIONS[3]}") $VPN_RELAY_SET_LOCATION ${VPN_CODES[3]} ;;
			*"${VPN_LOCATIONS[4]}") $VPN_RELAY_SET_LOCATION ${VPN_CODES[4]} ;;
			*"${VPN_LOCATIONS[5]}") $VPN_RELAY_SET_LOCATION ${VPN_CODES[5]} ;;
			*"${VPN_LOCATIONS[6]}") $VPN_RELAY_SET_LOCATION ${VPN_CODES[6]} ;;
			*"${VPN_LOCATIONS[7]}") $VPN_RELAY_SET_LOCATION ${VPN_CODES[7]} ;;
			*"${VPN_LOCATIONS[8]}") $VPN_RELAY_SET_LOCATION ${VPN_CODES[8]} ;;
			*"${VPN_LOCATIONS[9]}") $VPN_RELAY_SET_LOCATION ${VPN_CODES[9]} ;;
			*"${VPN_LOCATIONS[10]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[10]}" ;;
			*"${VPN_LOCATIONS[11]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[11]}" ;;
			*"${VPN_LOCATIONS[12]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[12]}" ;;
			*"${VPN_LOCATIONS[13]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[13]}" ;;
			*"${VPN_LOCATIONS[14]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[14]}" ;;
			*"${VPN_LOCATIONS[15]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[15]}" ;;
			*"${VPN_LOCATIONS[16]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[16]}" ;;
			*"${VPN_LOCATIONS[17]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[17]}" ;;
			*"${VPN_LOCATIONS[18]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[18]}" ;;
			*"${VPN_LOCATIONS[19]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[19]}" ;;
			*"${VPN_LOCATIONS[20]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[20]}" ;;
			*"${VPN_LOCATIONS[21]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[21]}" ;;
			*"${VPN_LOCATIONS[22]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[22]}" ;;
			*"${VPN_LOCATIONS[23]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[23]}" ;;
			*"${VPN_LOCATIONS[24]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[24]}" ;;
			*"${VPN_LOCATIONS[25]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[25]}" ;;
			*"${VPN_LOCATIONS[26]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[26]}" ;;
			*"${VPN_LOCATIONS[27]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[27]}" ;;
			*"${VPN_LOCATIONS[28]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[28]}" ;;
			*"${VPN_LOCATIONS[29]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[29]}" ;;
			*"${VPN_LOCATIONS[30]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[30]}" ;;
			*"${VPN_LOCATIONS[31]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[31]}" ;;
			*"${VPN_LOCATIONS[32]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[32]}" ;;
			*"${VPN_LOCATIONS[33]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[33]}" ;;
			*"${VPN_LOCATIONS[34]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[34]}" ;;
			*"${VPN_LOCATIONS[35]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[35]}" ;;
			*"${VPN_LOCATIONS[36]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[36]}" ;;
			*"${VPN_LOCATIONS[37]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[37]}" ;;
			*"${VPN_LOCATIONS[38]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[38]}" ;;
			*"${VPN_LOCATIONS[39]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[39]}" ;;
			*"${VPN_LOCATIONS[40]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[40]}" ;;
			*"${VPN_LOCATIONS[41]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[41]}" ;;
			*"${VPN_LOCATIONS[42]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[42]}" ;;
			*"${VPN_LOCATIONS[43]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[43]}" ;;
			*"${VPN_LOCATIONS[44]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[44]}" ;;
			*"${VPN_LOCATIONS[45]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[45]}" ;;
			*"${VPN_LOCATIONS[46]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[46]}" ;;
			*"${VPN_LOCATIONS[47]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[47]}" ;;
			*"${VPN_LOCATIONS[48]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[48]}" ;;
			*"${VPN_LOCATIONS[49]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[49]}" ;;
			*"${VPN_LOCATIONS[50]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[50]}" ;;
			*"${VPN_LOCATIONS[51]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[51]}" ;;
			*"${VPN_LOCATIONS[52]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[52]}" ;;
			*"${VPN_LOCATIONS[53]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[53]}" ;;
			*"${VPN_LOCATIONS[54]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[54]}" ;;
			*"${VPN_LOCATIONS[55]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[55]}" ;;
			*"${VPN_LOCATIONS[56]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[56]}" ;;
			*"${VPN_LOCATIONS[57]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[57]}" ;;
			*"${VPN_LOCATIONS[58]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[58]}" ;;
			*"${VPN_LOCATIONS[59]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[59]}" ;;
			*"${VPN_LOCATIONS[60]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[60]}" ;;
			*"${VPN_LOCATIONS[61]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[61]}" ;;
			*"${VPN_LOCATIONS[62]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[62]}" ;;
			*"${VPN_LOCATIONS[63]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[63]}" ;;
			*"${VPN_LOCATIONS[64]}") $VPN_RELAY_SET_LOCATION "${VPN_CODES[64]}" ;;
	    esac

	    if [ "$VPN_STATUS" = "$CONNECTED" ]; then
	        return
	    else
	        $VPN_CONNECT
	    fi
	fi
}


ip_address_to_clipboard() {
# finds your IP and copies to clipboard
	ip_address=$(ip_address_lookup)
	echo "$ip_address" | xclip -selection clipboard
}


# cases for polybar user_module.ini
case "$1" in
	-t|--toggle-connection) vpn_toggle_connection ;;
	-l|--location-menu) vpn_location_menu ;;
	-i|--ip-address) ip_address_to_clipboard ;;
	-n|--no-geoip) vpn_report --no-geoip ;;
	*) vpn_report ;;
esac
