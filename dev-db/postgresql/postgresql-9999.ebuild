# Copyright 1999-2023 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{10,11,12} )

inherit flag-o-matic git-r3 linux-info pam python-single-r1 systemd tmpfiles

KEYWORDS=""

SLOT="9999"

EGIT_REPO_URI="https://git.postgresql.org/git/postgresql.git"

LICENSE="POSTGRESQL GPL-2"
DESCRIPTION="PostgreSQL RDBMS"
HOMEPAGE="https://www.postgresql.org/"

IUSE="debug +icu kerberos ldap llvm +lz4 nls pam perl python +readline
	selinux server systemd ssl static-libs tcl uuid xml zlib zstd"

REQUIRED_USE="python? ( ${PYTHON_REQUIRED_USE} )"

CDEPEND="
>=app-eselect/eselect-postgresql-2.0
acct-group/postgres
acct-user/postgres
sys-apps/less
virtual/libintl
icu? ( dev-libs/icu:= )
kerberos? ( virtual/krb5 )
ldap? ( net-nds/openldap:= )
llvm? (
	sys-devel/llvm:=
	sys-devel/clang:=
)
lz4? ( app-arch/lz4 )
pam? ( sys-libs/pam )
perl? ( >=dev-lang/perl-5.8:= )
python? ( ${PYTHON_DEPS} )
readline? ( sys-libs/readline:0= )
ssl? ( >=dev-libs/openssl-0.9.6-r1:0= )
systemd? ( sys-apps/systemd )
tcl? ( >=dev-lang/tcl-8:0= )
uuid? ( dev-libs/ossp-uuid )
xml? ( dev-libs/libxml2 dev-libs/libxslt )
zlib? ( sys-libs/zlib )
zstd? ( app-arch/zstd )
"

# uuid flags -- depend on sys-apps/util-linux for Linux libcs, or if no
# supported libc in use depend on dev-libs/ossp-uuid. For BSD systems,
# the libc includes UUID functions.
UTIL_LINUX_LIBC=( elibc_{glibc,musl} )

nest_usedep() {
	local front back
	while [[ ${#} -gt 1 ]]; do
		front+="${1}? ( "
		back+=" )"
		shift
	done
	echo "${front}${1}${back}"
}

CDEPEND+="
uuid? (
	${UTIL_LINUX_LIBC[@]/%/? ( sys-apps/util-linux )}
	$(nest_usedep ${UTIL_LINUX_LIBC[@]/#/!} dev-libs/ossp-uuid)
)"

DEPEND="${CDEPEND}
>=dev-lang/perl-5.8
app-text/docbook-dsssl-stylesheets
app-text/docbook-sgml-dtd:4.5
app-text/docbook-xml-dtd:4.5
app-text/docbook-xsl-stylesheets
app-text/openjade
dev-libs/libxml2
dev-libs/libxslt
sys-devel/bison
sys-devel/flex
nls? ( sys-devel/gettext )
xml? ( virtual/pkgconfig )
"
RDEPEND="${CDEPEND}
selinux? ( sec-policy/selinux-postgresql )
"

pkg_pretend() {
	if ! use server; then
		elog "You are using a live ebuild that uses the current source code as it is"
		elog "available from PostgreSQL's Git repository at emerge time. Given such,"
		elog "the GNU Makefiles may be altered by upstream without notice and the"
		elog "documentation for this live version is not readily available"
		elog "online. Ergo, the ebuild maintainers will not support building a"
		elog "client-only and/or document-free version."
		ewarn "Building server anyway."
	fi
}

pkg_setup() {
	CONFIG_CHECK="~SYSVIPC" linux-info_pkg_setup

	use python && python-single-r1_pkg_setup
}

src_prepare() {
	# Set proper run directory
	sed "s|\(PGSOCKET_DIR\s\+\)\"/tmp\"|\1\"${EPREFIX}/run/postgresql\"|" \
		-i src/include/pg_config_manual.h || die

	# Rely on $PATH being in the proper order so that the correct
	# install program is used for modules utilizing PGXS in both
	# hardened and non-hardened environments. (Bug #528786)
	sed 's/@install_bin@/install -c/' -i src/Makefile.global.in || die

	if use pam ; then
		sed -e "s/\(#define PGSQL_PAM_SERVICE \"postgresql\)/\1-${SLOT}/" \
			-i src/backend/libpq/auth.c || \
			die 'PGSQL_PAM_SERVICE rename failed.'
	fi

	eapply_user
}

src_configure() {
	case ${CHOST} in
		*-darwin*|*-solaris*)
			use nls && append-libs intl
			;;
	esac

	export LDFLAGS_SL="${LDFLAGS}"
	export LDFLAGS_EX="${LDFLAGS}"

	local PO="${EPREFIX}"

	local i uuid_config=""
	if use uuid; then
		for i in ${UTIL_LINUX_LIBC[@]}; do
			use ${i} && uuid_config="--with-uuid=e2fs"
		done
		[[ -z $uuid_config ]] && uuid_config="--with-uuid=ossp"
	fi

	local myconf="\
		--prefix="${PO}/usr/$(get_libdir)/postgresql-${SLOT}" \
		--datadir="${PO}/usr/share/postgresql-${SLOT}" \
		--includedir="${PO}/usr/include/postgresql-${SLOT}" \
		--mandir="${PO}/usr/share/postgresql-${SLOT}/man" \
		--sysconfdir="${PO}/etc/postgresql-${SLOT}" \
		--with-system-tzdata="${PO}/usr/share/zoneinfo" \
		$(use_enable debug) \
		$(use_enable nls) \
		$(use_with icu) \
		$(use_with kerberos gssapi) \
		$(use_with ldap) \
		$(use_with llvm) \
		$(use_with lz4) \
		$(use_with pam) \
		$(use_with perl) \
		$(use_with python) \
		$(use_with readline) \
		$(use_with ssl openssl) \
		$(use_with tcl) \
		$(use_with xml libxml) \
		$(use_with xml libxslt) \
		$(use_with zlib) \
		$(use_with zstd ) \
		$(use_with systemd) \
		${uuid_config}"
	if use alpha; then
		myconf+=" --disable-spinlocks"
	else
		# Should be the default but just in case
		myconf+=" --enable-spinlocks"
	fi
	econf ${myconf}
}

src_compile() {
	emake world
}

src_install() {
	emake DESTDIR="${D}" install-world

	dodoc README HISTORY doc/TODO

	insinto /etc/postgresql-${SLOT}
	newins src/bin/psql/psqlrc.sample psqlrc

	# Don't delete libpg{port,common}.a (Bug #571046). They're always
	# needed by extensions utilizing PGXS.
	use static-libs || \
		find "${ED}" -name '*.a' ! -name libpgport.a ! -name libpgcommon.a \
			 -delete

	sed -e "s|@SLOT@|${SLOT}|g" -e "s|@LIBDIR@|$(get_libdir)|g" \
		"${FILESDIR}/${PN}.confd-9.3" | newconfd - ${PN}-${SLOT}

	sed -e "s|@SLOT@|${SLOT}|g" -e "s|@LIBDIR@|$(get_libdir)|g" \
		"${FILESDIR}/${PN}.init-9.3-r1" | newinitd - ${PN}-${SLOT}

	if use systemd; then
		sed -e "s|@SLOT@|${SLOT}|g" -e "s|@LIBDIR@|$(get_libdir)|g" \
			"${FILESDIR}/${PN}.service-9.6-r1" | \
			systemd_newunit - ${PN}-${SLOT}.service
		newtmpfiles "${FILESDIR}"/${PN}.tmpfiles ${PN}-${SLOT}.conf
	fi

	newbin "${FILESDIR}"/${PN}-check-db-dir ${PN}-${SLOT}-check-db-dir

	use pam && pamd_mimic system-auth ${PN}-${SLOT} auth account session

	local f bn
	for f in $(find "${ED}/usr/$(get_libdir)/postgresql-${SLOT}/bin" \
					-mindepth 1 -maxdepth 1)
	do
		bn=$(basename "${f}")
		# Temporarily tack on tmp to workaround a file collision
		# issue. This is only necessary for 9.7 and earlier. 10 never
		# had this issue.
		dosym "../$(get_libdir)/postgresql-${SLOT}/bin/${bn}" \
			  "/usr/bin/${bn}${SLOT/.}tmp"
	done

	# Create slot specific man pages
	local bn f mansec slotted_name
	for mansec in 1 3 7 ; do
		local rel_manpath="../../postgresql-${SLOT}/man/man${mansec}"

		mkdir -p "${ED}"/usr/share/man/man${mansec} || die "making man dir"
		pushd "${ED}"/usr/share/man/man${mansec} > /dev/null || die "pushd failed"

		for f in "${ED}/usr/share/postgresql-${SLOT}/man/man${mansec}"/* ; do
			bn=$(basename "${f}")
			slotted_name=${bn%.${mansec}}${SLOT}.${mansec}
			case ${bn} in
				TABLE.7|WITH.7)
					echo ".so ${rel_manpath}/SELECT.7" > ${slotted_name}
					;;
				*)
					echo ".so ${rel_manpath}/${bn}" > ${slotted_name}
					;;
			esac
		done

		popd > /dev/null
	done

	if use prefix ; then
		keepdir /run/postgresql
		fperms 1775 /run/postgresql
	fi
}

pkg_preinst() {
	# Find all of the slot-specific symlinks, if any, in /usr/bin (e.g.,
	# /usr/bin/psql97). They may have been created by the
	# postgresql.eselect module, but they're handled within this ebuild
	# now. It's alright if we momentarily delete /usr/bin/psql as it
	# will be recreated by the eselect module in pkg_ppostinst().  We
	# only worry about the 9.7 slot as that's the last slot that had its
	# slot-specific links generated by eselect.
	#
	# This can be removed when 10 is the lowest slot in the tree.
	local canonicalise
	if type -p realpath > /dev/null; then
		canonicalise=realpath
	elif type -p readlink > /dev/null; then
		canonicalise='readlink -f'
	else
		# can't die, subshell
		die "No readlink nor realpath found, cannot canonicalise"
	fi

	local l
	# First remove any symlinks in /usr/bin that may have been created
	# by the old eselect
	for l in $(find "${ROOT}/usr/bin" -mindepth 1 -maxdepth 1 -type l) ; do
		[[ $(${canonicalise} "${l}") == *postgresql-9.7* ]] && rm "${l}"
	done

	# Then move the symlinks created by the ebuild to their proper place.
	for l in "${ED}"/usr/bin/*tmp ; do
		mv "${l}" "${l%tmp}" \
			|| ewarn "Couldn't rename $(basename ${l}) to $(basename ${l%tmp})"
	done
}

pkg_postinst() {
	use systemd && tmpfiles_process ${PN}-${SLOT}.conf
	postgresql-config update

	elog "If you need a global psqlrc-file, you can place it in:"
	elog "    ${EROOT}/etc/postgresql-${SLOT}/"

	elog
	elog "Gentoo specific documentation:"
	elog "https://wiki.gentoo.org/wiki/PostgreSQL"
	elog
	elog "Official documentation:"
	elog "${EROOT}/usr/share/doc/${PF}/html"
	elog
	elog "The default location of the Unix-domain socket is:"
	elog "    ${EROOT}/run/postgresql/"
	elog
	elog "Before initializing the database, you may want to edit PG_INITDB_OPTS"
	elog "so that it contains your preferred locale, and other options, in:"
	elog "    ${EROOT}/etc/conf.d/postgresql-${SLOT}"
	elog
	elog "Then, execute the following command to setup the initial database"
	elog "environment:"
	elog "    emerge --config =${CATEGORY}/${PF}"
}

pkg_prerm() {
	if [[ -z ${REPLACED_BY_VERSION} ]] ; then
		ewarn "Have you dumped and/or migrated the ${SLOT} database cluster?"
		ewarn "\thttps://wiki.gentoo.org/wiki/PostgreSQL/QuickStart#Migrating_PostgreSQL"

		ebegin "Resuming removal in 10 seconds (Control-C to cancel)"
		sleep 10
		eend 0
	fi
}

pkg_postrm() {
	postgresql-config update
}

pkg_config() {
	[[ -f "${EROOT}/etc/conf.d/postgresql-${SLOT}" ]] \
		&& source "${EROOT}/etc/conf.d/postgresql-${SLOT}"
	[[ -z "${PGDATA}" ]] && PGDATA="${EROOT}/etc/postgresql-${SLOT}/"
	[[ -z "${DATA_DIR}" ]] \
		&& DATA_DIR="${EROOT}/var/lib/postgresql/${SLOT}/data"

	# environment.bz2 may not contain the same locale as the current system
	# locale. Unset and source from the current system locale.
	if [ -f "${EROOT}/etc/env.d/02locale" ]; then
		unset LANG
		unset LC_CTYPE
		unset LC_NUMERIC
		unset LC_TIME
		unset LC_COLLATE
		unset LC_MONETARY
		unset LC_MESSAGES
		unset LC_ALL
		source "${EROOT}/etc/env.d/02locale"
		[ -n "${LANG}" ] && export LANG
		[ -n "${LC_CTYPE}" ] && export LC_CTYPE
		[ -n "${LC_NUMERIC}" ] && export LC_NUMERIC
		[ -n "${LC_TIME}" ] && export LC_TIME
		[ -n "${LC_COLLATE}" ] && export LC_COLLATE
		[ -n "${LC_MONETARY}" ] && export LC_MONETARY
		[ -n "${LC_MESSAGES}" ] && export LC_MESSAGES
		[ -n "${LC_ALL}" ] && export LC_ALL
	fi

	einfo "You can modify the paths and options passed to initdb by editing:"
	einfo "    ${EROOT}/etc/conf.d/postgresql-${SLOT}"
	einfo
	einfo "Information on options that can be passed to initdb are found at:"
	einfo "    https://www.postgresql.org/docs/${SLOT}/static/creating-cluster.html"
	einfo "    https://www.postgresql.org/docs/${SLOT}/static/app-initdb.html"
	einfo
	einfo "PG_INITDB_OPTS is currently set to:"
	if [[ -z "${PG_INITDB_OPTS}" ]] ; then
		einfo "    (none)"
	else
		einfo "    ${PG_INITDB_OPTS}"
	fi
	einfo
	einfo "Configuration files will be installed to:"
	einfo "    ${PGDATA}"
	einfo
	einfo "The database cluster will be created in:"
	einfo "    ${DATA_DIR}"
	einfo

	ebegin "Continuing initialization in 5 seconds (Control-C to cancel)"
	sleep 5
	eend 0

	if [ -n "$(ls -A ${DATA_DIR} 2> /dev/null)" ] ; then
		eerror "The given directory, '${DATA_DIR}', is not empty."
		eerror "Modify DATA_DIR to point to an empty directory."
		die "${DATA_DIR} is not empty."
	fi

	einfo "Creating the data directory ..."
	if [[ ${EUID} == 0 ]] ; then
		mkdir -p "${DATA_DIR}"
		chown -Rf postgres:postgres "${DATA_DIR}"
		chmod 0700 "${DATA_DIR}"
	fi

	einfo "Initializing the database ..."

	if [[ ${EUID} == 0 ]] ; then
		su - postgres -c "${EROOT}/usr/$(get_libdir)/postgresql-${SLOT}/bin/initdb -D \"${DATA_DIR}\" ${PG_INITDB_OPTS}"
	else
		"${EROOT}"/usr/$(get_libdir)/postgresql-${SLOT}/bin/initdb -U postgres -D "${DATA_DIR}" ${PG_INITDB_OPTS}
	fi

	if [[ "${DATA_DIR%/}" != "${PGDATA%/}" ]] ; then
		mv "${DATA_DIR%/}"/{pg_{hba,ident},postgresql}.conf "${PGDATA}"
		ln -s "${PGDATA%/}"/{pg_{hba,ident},postgresql}.conf "${DATA_DIR%/}"
	fi

	# unix_socket_directory has no effect in postgresql.conf as it's
	# overridden in the initscript
	sed '/^#unix_socket_directories/,+1d' -i "${PGDATA%/}"/postgresql.conf

	cat <<- EOF >> "${PGDATA%/}"/postgresql.conf
		# This is here because of https://bugs.gentoo.org/show_bug.cgi?id=518522
		# On the off-chance that you might need to work with UTF-8 encoded
		# characters in PL/Perl
		plperl.on_init = 'use utf8; use re; package utf8; require "utf8_heavy.pl";'
	EOF

	einfo "The autovacuum function, which was in contrib, has been moved to the main"
	einfo "PostgreSQL functions starting with 8.1, and starting with 8.4 is now enabled"
	einfo "by default. You can disable it in the cluster's:"
	einfo "    ${PGDATA%/}/postgresql.conf"
	einfo
	if ! use systemd; then
		einfo "The PostgreSQL server, by default, will log events to:"
		einfo "    ${DATA_DIR%/}/postmaster.log"
		einfo
	fi
	if use prefix ; then
		einfo "The location of the configuration files have moved to:"
		einfo "    ${PGDATA}"
		einfo "To start the server:"
		einfo "    pg_ctl start -D ${DATA_DIR} -o '-D ${PGDATA} --data-directory=${DATA_DIR}'"
		einfo "To stop:"
		einfo "    pg_ctl stop -D ${DATA_DIR}"
		einfo
		einfo "Or move the configuration files back:"
		einfo "mv ${PGDATA}*.conf ${DATA_DIR}"
	elif use systemd; then
		einfo "You should use the 'postgresql-${SLOT}.service' unit to run PostgreSQL"
		einfo "instead of 'pg_ctl'."
	else
		einfo "You should use the '${EROOT}/etc/init.d/postgresql-${SLOT}' script to run PostgreSQL"
		einfo "instead of 'pg_ctl'."
	fi
}

src_test() {
	if [[ ${UID} -ne 0 ]] ; then
		# Some ICU tests fail if LC_CTYPE and LC_COLLATE aren't the same. We set
		# LC_CTYPE to be equal to LC_COLLATE since LC_COLLATE is set by Portage.
		local old_ctype=${LC_CTYPE}
		export LC_CTYPE=${LC_COLLATE}
		emake check
		export LC_CTYPE=${old_ctype}

		einfo "If you think other tests besides the regression tests are necessary, please"
		einfo "submit a bug including a patch for this ebuild to enable them."
	else
		ewarn 'Tests cannot be run as root. Enable "userpriv" in FEATURES.'
		ewarn 'Skipping.'
	fi
}
