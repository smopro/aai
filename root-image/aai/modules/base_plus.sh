#!/bin/sh
#
#
#
#   Copyright (c) 2012-2013 Anthony Lyappiev <archlinux@antavr.ru>
#   http://archlinux.antavr.ru
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

# Добавляем функцию модуля в главное меню, пробел в конце обязательно!
MAIN_CASE+=('base_plus')

#===============================================================================
# Сигнальная переменная успешного завершения функции модуля,
# может потребоваться для других модулей, для проверки зависимости
RUN_BASE_PLUS=
TXT_BASE_PLUS_MAIN="$(gettext 'Расширенная базовая система')"

SERVICES=''

#===============================================================================

# Выводим строку пункта главного меню
str_base_plus()
{
	local TEMP

	[[ "${RUN_BASE_PLUS}" ]] && TEMP="\Zb\Z2($(gettext 'ВЫПОЛНЕНО'))\Zn"
	echo "${TXT_BASE_PLUS_MAIN} ${TEMP}"
}

# Функция выполнения из главного меню
run_base_plus()
{
	local TEMP

	if [[ "${NO_DEBUG}" ]]
	then
# Проверяем выполнен ли local пункт меню
		[[ ! "${RUN_BASE}" ]] && TEMP+=" $(str_base)\n"

		if [[ "${TEMP}" ]]
		then
			dialog_warn \
				"\Zb\Z1$(gettext 'Не выполнены обязательные пункты меню')\Zn\n${TEMP}"
			return 1
		fi

		if [[ "${RUN_BASE_PLUS}" ]]
		then
			dialog_warn \
				"\Zb\Z1$(gettext 'Пункт') \"${TXT_BASE_PLUS_MAIN}\" $(gettext 'уже выполнен')\Zn"
			return 1
		fi
	fi

	base_plus_install

#===============================================================================
# Настраиваем правильное определение саундов если их несколько
#===============================================================================
	local CARDS
	local CARD_IND
	local CARD
	local CARD_ID
	local MODULE

	TEMP="$(base_plus_dialog_sound)"
	if [[ ! -n "${TEMP}" ]]
	then
		msg_log "$(gettext 'Настраиваю') /etc/modprobe.d/alsa-base.conf"
		get_sounds \
		| while read CARDS
		do
			eval "$(awk -F ',' '{print "CARD="$1"; CARD_ID="$2"; MODULE="$3";"}' <<< "${CARDS}")"
			echo ''
			echo "## -- ${MODULE} --"
			echo "alias snd-card-${CARD} ${MODULE}"
			echo "alias snd-slot-${CARD} ${MODULE}"
			echo "options ${MODULE} index=${CARD} id=${CARD_ID}"
		done > "${NS_PATH}/etc/modprobe.d/alsa-base.conf"
	else
		case "${TEMP}" in
			'none')
				echo ''
				;;
			*)
				msg_log "$(gettext 'Настраиваю') /etc/modprobe.d/alsa-base.conf"
				CARD_IND=0
				{
				get_sounds \
				| while read CARDS
				do
					global CARD_IND
					eval "$(awk -F ',' '{print "CARD="$1"; CARD_ID="$2"; MODULE="$3";"}' <<< "${CARDS}")"
					[[ "${CARD}" != "${TEMP}" ]] && continue
					echo ''
					echo "## -- ${MODULE} --"
					echo "alias snd-card-${CARD_IND} ${MODULE}"
					echo "alias snd-slot-${CARD_IND} ${MODULE}"
					echo "options ${MODULE} index=${CARD_IND} id=${CARD_ID}"
					break
				done
				CARD_IND=$((${CARD_IND}+1))
				get_sounds \
				| while read CARDS
				do
					eval "$(awk -F ',' '{print "CARD="$1"; CARD_ID="$2"; MODULE="$3";"}' <<< "${CARDS}")"
					[[ "${CARD}" == "${TEMP}" ]] && continue
					echo ''
					echo "## -- ${MODULE} --"
					echo "alias snd-card-${CARD_IND} ${MODULE}"
					echo "alias snd-slot-${CARD_IND} ${MODULE}"
					echo "options ${MODULE} index=${CARD_IND} id=${CARD_ID}"
					CARD_IND=$((${CARD_IND}+1))
				done
				} > "${NS_PATH}/etc/modprobe.d/alsa-base.conf"
				;;
		esac
	fi
#-------------------------------------------------------------------------------


	SERVICES="$(base_plus_dialog_service)"
	for SERVICE in ${SERVICES}
	do
		chroot_run systemctl enable "${SERVICE}"
	done

#===============================================================================
# Отключаем ненужное!
#===============================================================================
	chroot_run systemctl mask 'syslog.service'
	chroot_run systemctl mask 'plymouth-start.service'
	chroot_run systemctl mask 'plymouth-quit-wait.service'
#-------------------------------------------------------------------------------



#===============================================================================
# Меняем метод переключения раскладки на alt+shift
#===============================================================================
	dialog_yesno \
		"$(gettext 'Установить переключение раскладки')" \
		"$(gettext 'Установить переключение раскладки клавиатуры в консоле на') alt+shift ?"

	case "${?}" in
		'0') #Yes
			conv_keymap
			;;
	esac
#-------------------------------------------------------------------------------



	git_commit
}

get_sounds()
{
	local CARD
	local CARD_ID
	local MODULE

	[[ ! -e /proc/asound/cards ]] && return 1
	for CARD in $(awk '$1 ~ /^[0-9]{1,2}/{print $1}' /proc/asound/cards)
	do
		MODULE="$(awk '$1 ~ /^'${CARD}'/{print $2}' /proc/asound/modules)"
		CARD_ID="$(cat /proc/asound/card${CARD}/id)"
		echo "${CARD},${CARD_ID},${MODULE}"
	done
}

base_plus_dialog_sound()
{
	msg_log "$(gettext 'Запуск диалога'): \"${FUNCNAME}$(for ((TEMP=1; TEMP<=${#}; TEMP++)); do echo -n " \$${TEMP}='$(eval "echo \"\${${TEMP}}\"")'"; done)\"" 'noecho'

	local RETURN

	local TITLE="${TXT_BASE_PLUS_MAIN}"
	local HELP_TXT="\n$(gettext 'Выберите звуковую карту по умолчанию')\n"

	local DEFAULT_ITEM='0'
	local ITEMS="'none' 'none'"

	ITEMS+="$(get_sounds | awk -F ',' '{print " " sq $1 sq " " sq $2 " " $3 sq}' sq=\')"

	RETURN="$(dialog_menu "${TITLE}" "${DEFAULT_ITEM}" "${HELP_TXT}" "${ITEMS}"  '--no-cancel')"

	echo "${RETURN}"
	msg_log "$(gettext 'Выход из диалога'): \"${FUNCNAME} return='${RETURN}'\"" 'noecho'
}

base_plus_dialog_service()
{
	msg_log "$(gettext 'Запуск диалога'): \"${FUNCNAME}$(for ((TEMP=1; TEMP<=${#}; TEMP++)); do echo -n " \$${TEMP}='$(eval "echo \"\${${TEMP}}\"")'"; done)\"" 'noecho'

	local RETURN

	local TITLE="${TXT_BASE_PLUS_MAIN}"
	local HELP_TXT="\n$(gettext 'Включение сервисов')\n"

	local ITEMS="${SERVICES}"
#     ITEMS+=" 'systemd-readahead-collect' '-' 'off'"
#     ITEMS+=" 'systemd-readahead-replay' '-' 'off'"

	RETURN="$(dialog_checklist "${TITLE}" "${HELP_TXT}" "${ITEMS}" '--no-cancel')"

	echo "${RETURN}"
	msg_log "$(gettext 'Выход из диалога'): \"${FUNCNAME} return='${RETURN}'\"" 'noecho'
}

#yaourt -S vlc
#yaourt -Si avahi libdvdcss libavc1394 libdc1394 kdelibs libva-vdpau-driver libva-intel-driver libbluray flac oss portaudio twolame  projectm libcaca libgme librsvg gnome-vfs libgoom2 vcdimager xosd aalib libmtp fluidsynth smbclient libcdio opus libssh2
#ошибка: пакет 'libva-vdpau-driver' не найден
#ошибка: пакет 'libva-intel-driver' не найден

# Дополнительная настройка системы
base_plus_install()
{
	local SERVICE

	local PACS


	pkgs_base_plus_yaourt

#===============================================================================
# Создаем папки и перемещаем кеш пакетов для создания бэкапов.
#===============================================================================
	msg_log "$(gettext 'Перемещаю кеш пакетов') > /home/sys-backup/packages"
	msg_info "$(gettext 'Пожалуйста, подождите')..."
	mkdir -p "${NS_PATH}/home/sys-backup/"{bakup,packages,srcpackages}
	chown -Rh root:wheel "${NS_PATH}/home/sys-backup"
	chmod -R g=rwx "${NS_PATH}/home/sys-backup"
	mv "${NS_PATH}"/var/cache/pacman/pkg/* "${NS_PATH}/home/sys-backup/packages"

	msg_log "$(gettext 'Настраиваю') /etc/pacman.conf"
	sed -i '
# Mеняем путь к кешу пакетов
/^CacheDir *=/s/^/#/;
0,/^#CacheDir *=/{
//{
	a CacheDir    = /home/sys-backup/packages/
};
};
' "${NS_PATH}/etc/pacman.conf"
# Меняем путь к кешу пакетов и кешу исходных кодов пакетов
	msg_log "$(gettext 'Настраиваю') /etc/makepkg.conf"
	sed -i '
/^#PKGDEST=/{
	a PKGDEST=/home/sys-backup/packages
};
/^#SRCPKGDEST=/{
	a SRCPKGDEST=/home/sys-backup/srcpackages
};
' "${NS_PATH}/etc/makepkg.conf"
	git_commit
#-------------------------------------------------------------------------------



#===============================================================================
# Добавляем сервис и rc.local для быстрого добавления своих команд в процесс загрузки
#===============================================================================
#Включаем Nul Lock в консоле
	msg_log "$(gettext 'Настраиваю') /etc/rc.local"
	cat "${DBDIR}modules/etc/rc.local" > "${NS_PATH}/etc/rc.local"
	chmod +x "${NS_PATH}/etc/rc.local"

# Создаем и включаем rc-local.service
	msg_log "$(gettext 'Настраиваю') /usr/local/lib/systemd/system/rc-local.service"
	mkdir -p "${NS_PATH}/usr/local/lib/systemd/system"
	mkdir -p "${NS_PATH}/usr/local/lib/systemd/user"
	cat "${DBDIR}modules/usr/local/lib/systemd/system/rc-local.service" > "${NS_PATH}/usr/local/lib/systemd/system/rc-local.service"
	cat "${DBDIR}modules/usr/local/lib/systemd/system/autologin@.service" > "${NS_PATH}/usr/local/lib/systemd/system/autologin@.service"

	git_commit

	SERVICES+=" 'rc-local.service' '-' 'on'"
#-------------------------------------------------------------------------------



#===============================================================================
# Добавляем некоторые параметры ядра
#===============================================================================
	msg_log "$(gettext 'Настраиваю') /etc/sysctl.d/kernel.conf"
	cat "${DBDIR}modules/etc/sysctl.d/kernel.conf" > "${NS_PATH}/etc/sysctl.d/kernel.conf"
#     msg_log "$(gettext 'Настраиваю') /etc/sysctl.d/net.conf"
#     cat "${DBDIR}modules/etc/sysctl.d/net.conf" > "${NS_PATH}/etc/sysctl.d/net.conf"
#-------------------------------------------------------------------------------



#===============================================================================
# Включаем systemd для пользователя
#===============================================================================
	msg_log "$(gettext 'Настраиваю') /etc/pam.d/systemd-user"
	sed -i '
# Включаем systemd для пользователя
s/system-auth/system-login/g
' "${NS_PATH}/etc/pam.d/systemd-user"
#-------------------------------------------------------------------------------



#===============================================================================
# Устраняем глюк при входе в ждущий режим
#===============================================================================
	msg_log "$(gettext 'Настраиваю') /etc/tmpfiles.d/disable-wakeup-usb.conf"
	cat "${DBDIR}modules/etc/tmpfiles.d/disable-wakeup-usb.conf" > "${NS_PATH}/etc/tmpfiles.d/disable-wakeup-usb.conf"
	git_commit
#-------------------------------------------------------------------------------



#===============================================================================
# Настройка некоторых утилит
#===============================================================================
# Максимальное сжатие для XZ
	msg_log "$(gettext 'Настраиваю') /etc/profile.d/xz.sh"
	cat "${DBDIR}modules/etc/profile.d/xz.sh" > "${NS_PATH}/etc/profile.d/xz.sh"
	chmod +x "${NS_PATH}/etc/profile.d/xz.sh"

# Формат pax в tar по умолчанию
	msg_log "$(gettext 'Настраиваю') /etc/profile.d/tar.sh"
	cat "${DBDIR}modules/etc/profile.d/tar.sh" > "${NS_PATH}/etc/profile.d/tar.sh"
	chmod +x "${NS_PATH}/etc/profile.d/tar.sh"

# Что бы вывод ls был цветной
	msg_log "$(gettext 'Настраиваю') /etc/profile.d/ls.sh"
	cat "${DBDIR}modules/etc/profile.d/ls.sh" > "${NS_PATH}/etc/profile.d/ls.sh"
	chmod +x "${NS_PATH}/etc/profile.d/ls.sh"

# Что бы вывод grep был цветной
	msg_log "$(gettext 'Настраиваю') /etc/profile.d/grep.sh"
	cat "${DBDIR}modules/etc/profile.d/grep.sh" > "${NS_PATH}/etc/profile.d/grep.sh"
	chmod +x "${NS_PATH}/etc/profile.d/grep.sh"

# Редактор по умолчанию
	msg_log "$(gettext 'Настраиваю') /etc/profile.d/editor.sh"
	cat "${DBDIR}modules/etc/profile.d/editor.sh" > "${NS_PATH}/etc/profile.d/editor.sh"
	chmod +x "${NS_PATH}/etc/profile.d/editor.sh"

# Что бы не стирался вывод man
	msg_log "$(gettext 'Настраиваю') /etc/profile.d/less.sh"
	cat "${DBDIR}modules/etc/profile.d/less.sh" > "${NS_PATH}/etc/profile.d/less.sh"
	chmod +x "${NS_PATH}/etc/profile.d/less.sh"

	git_commit
#-------------------------------------------------------------------------------



#===============================================================================
# Включаю zcache2 для экономии памяти
#===============================================================================
	msg_log "$(gettext 'Включаю ') zcache2"
	cat "${DBDIR}modules/etc/modules-load.d/zcache.conf" > "${NS_PATH}/etc/modules-load.d/zcache.conf"
	git_commit
#-------------------------------------------------------------------------------



#===============================================================================
# Для определения ssd и установки планировщика
#===============================================================================
	msg_log "$(gettext 'Настраиваю') /etc/udev/rules.d/60-schedulers.rules"
	cat "${DBDIR}modules/etc/udev/rules.d/60-schedulers.rules" > "${NS_PATH}/etc/udev/rules.d/60-schedulers.rules"
	git_commit
#-------------------------------------------------------------------------------



#===============================================================================
# Для исправления бага с консольным шрифтом
#===============================================================================
	msg_log "$(gettext 'Настраиваю') /etc/udev/rules.d/96-fb-all-vcs-setup.rules"
	cat "${DBDIR}modules/etc/udev/rules.d/96-fb-all-vcs-setup.rules" > "${NS_PATH}/etc/udev/rules.d/96-fb-all-vcs-setup.rules"
	msg_log "$(gettext 'Настраиваю') /etc/udev/all-vcs-set.sh"
	cat "${DBDIR}modules/etc/udev/all-vcs-set.sh" > "${NS_PATH}/etc/udev/all-vcs-set.sh"
	chmod +x "${NS_PATH}/etc/udev/all-vcs-set.sh"
	git_commit
#-------------------------------------------------------------------------------



#===============================================================================
# Для монтирования не смонтированных дисков кликом мышки
#===============================================================================
	msg_log "$(gettext 'Настраиваю') /etc/polkit-1/rules.d/10-udisks.rules"
	mkdir -p "${NS_PATH}/etc/polkit-1/rules.d"
	cat "${DBDIR}modules/etc/polkit-1/rules.d/10-udisks.rules" > "${NS_PATH}/etc/polkit-1/rules.d/10-udisks.rules"

	SET_USER_GRUPS+=',storage'

	git_commit
#-------------------------------------------------------------------------------



#===============================================================================
# Добавляю .face.icon
#===============================================================================
	msg_log "$(gettext 'Настраиваю') /etc/skel/.face.icon"
	cp "${DBDIR}modules/etc/skel/.face.icon" "${NS_PATH}/etc/skel/.face.icon"

	git_commit
#-------------------------------------------------------------------------------



#===============================================================================
# Добавляю keymap в mkinitcpio
#===============================================================================
	msg_log "$(gettext 'Добавляю') keymap > /etc/mkinitcpio.conf"
	sed -i '
# Добавляем хук keymap
/^HOOKS=/{
	h;
	s/^/#/;
	P;g;
	//{
	s/keymap//g;s/ \{1,\}/ /g;
	s/fsck/fsck keymap/;
	};
};
# Меняем компресор на xz
/^COMPRESSION=/s/^/#/;
0,/^#COMPRESSION=/{
//{
	a COMPRESSION="xz"
};
};
# Устанавливаем параметры на максимальное сжатие
/^COMPRESSION_OPTIONS=/s/^/#/;
0,/^#COMPRESSION_OPTIONS=/{
//{
	a COMPRESSION_OPTIONS="-9eT 2"
};
};
' "${NS_PATH}/etc/mkinitcpio.conf"

	git_commit
#-------------------------------------------------------------------------------

	pkgs_base_plus_aspell_loc

	pkgs_base_plus_alsa

	pkgs_base_plus_squashfs

	pkgs_base_plus_archives

	pkgs_base_plus_fs

	pkgs_base_plus_crypt

	pkgs_base_plus_cdemu

	pkgs_base_plus_hd

	pkgs_base_plus_man_pages_loc

	pkgs_base_plus_laptop

	pkgs_base_plus_utils

	pkgs_base_plus_linux_tools

	pkgs_base_plus_lirc

	pkgs_base_plus_postfix

	pkgs_base_plus_vsftpd

	pkgs_base_plus_mlocate

	pkgs_base_plus_sensors

# 	pkgs_base_plus_preload

	pkgs_base_plus_aria2

	pkgs_base_plus_net

	pkgs_base_plus_iptables

	pkgs_base_plus_ufw

#	pkgs_base_plus_timestamp

	chroot_run mkinitcpio -p linux

	RUN_BASE_PLUS=1
	return 0
}

#udevadm info -a -p `udevadm info -q path -n /dev/fb0`
conv_keymap__add_strs()
{
	local P_KEYNAME_S="${1}"
	local P_KEYNAME_A="${2}"
	local P_KEYMAP_FILE="${3}"

	local KEYCODE
	local STR

	grep "${P_KEYNAME_S}$" "${P_KEYMAP_FILE}" \
	| while read STR
	do
		KEYCODE=(${STR})
		sed -i "/${STR}/ a${P_KEYNAME_A} keycode ${KEYCODE[1]} = AltGr_Lock\naltgr ${P_KEYNAME_A} keycode ${KEYCODE[1]} = AltGr_Lock" "${P_KEYMAP_FILE}"
	done
}

conv_keymap__conv_alt_sh()
{
	local P_KEYMAP="${1}"

	local KEYMAPSDIR='/etc/kbd/keymaps/'
	mkdir -p "${NS_PATH}${KEYMAPSDIR}"

	local KEYMAP_FILE="$(find "${NS_PATH}/usr/share/kbd/keymaps/" -iname "${P_KEYMAP}.map.gz")"
	[[ ! "${KEYMAP_FILE}" ]] && msg_error "$(gettext 'Файл раскладки клавиатуры не найден!!!')" 0 && return

	KEYMAPSDIR+="${P_KEYMAP}.map"
	local KEYMAP_FILE_NEW="${NS_PATH}${KEYMAPSDIR}"

	gzip -dc "${KEYMAP_FILE}" | grep -v 'AltGr_Lock' | sed 's/#\(.*\)//;s/^[ \t]*//;s/[ \t]*$//;s/ \{1,\}/ /g' | sed '/^ *$/d' > "${KEYMAP_FILE_NEW}"

	conv_keymap__add_strs 'Alt' 'shift' "${KEYMAP_FILE_NEW}"
	conv_keymap__add_strs 'Shift' 'alt' "${KEYMAP_FILE_NEW}"
	sed -i "1i # Gen `date '+%Y-%m-%d %H:%M'`. From ${P_KEYMAP}.map.gz. Mode is switched by the Alt+Shift" "${KEYMAP_FILE_NEW}"

	gzip -9f "${KEYMAP_FILE_NEW}"

	echo "${KEYMAPSDIR}.gz"
}

conv_keymap()
{
	local KEYMAP_FILE_NEW
	local KEYMAP
	local KEYMAP_TOGGLE
	local FONT
	local FONT_MAP
	local FONT_UNIMAPMAP

	source "${NS_PATH}/etc/vconsole.conf"

	if [[ "${KEYMAP}" ]] && [[ ! -f "${NS_PATH}${KEYMAP}" ]]
	then
		msg_log "$(gettext 'Изменяю раскладку') KEYMAP=${KEYMAP}"
		KEYMAP_FILE_NEW="$(conv_keymap__conv_alt_sh "${KEYMAP}")"
		[[ "${KEYMAP_FILE_NEW}" ]] && sed -i "
/^KEYMAP=/s/^/#/;
0,/^#KEYMAP=/{
//{
	a KEYMAP='$(sed 's/\//\\\//g' <<< "${KEYMAP_FILE_NEW}")'
};
};
" "${NS_PATH}/etc/vconsole.conf"
	fi

	if [[ "${KEYMAP_TOGGLE}" ]] && [[ ! -f "${NS_PATH}${KEYMAP_TOGGLE}" ]]
	then
		msg_log "$(gettext 'Изменяю раскладку') KEYMAP_TOGGLE=${KEYMAP_TOGGLE}"
		KEYMAP_FILE_NEW="$(conv_keymap__conv_alt_sh "${KEYMAP_TOGGLE}")"
		[[ "${KEYMAP_FILE_NEW}" ]] && sed -i "
/^KEYMAP_TOGGLE=/s/^/#/;
0,/^#KEYMAP_TOGGLE=/{
//{
	a KEYMAP_TOGGLE='$(sed 's/\//\\\//g' <<< "${KEYMAP_FILE_NEW}")'
};
};
" "${NS_PATH}/etc/vconsole.conf"
	fi
}

hwdetect_net()
{
	local IFACE
	local IFACE_NAME

	for IFACE in /sys/class/net/*
	do
		IFACE_NAME="${IFACE/\/sys\/class\/net\//}"
		[[ "${IFACE_NAME}" == 'lo' ]] && continue
		IFACE_NAME="${IFACE_NAME/eth/net}"
		IFACE_NAME="${IFACE_NAME/wlan/wifi}"
		echo "SUBSYSTEM==\"net\", ATTR{address}==\"$(cat ${IFACE}/address)\", NAME=\"${IFACE_NAME}\""
	done
}

