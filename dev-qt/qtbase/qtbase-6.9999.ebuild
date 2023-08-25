# Copyright 2021-2023 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit qt6-build

DESCRIPTION="Cross-platform application development framework"

if [[ ${QT6_BUILD_TYPE} == release ]]; then
	KEYWORDS="~amd64"
fi

declare -A QT6_IUSE=(
	[global]="+ssl +udev zstd"
	[core]="icu systemd"
	[modules]="+concurrent +dbus +gui +network +sql +xml"

	[gui]="
		+X accessibility eglfs evdev gles2-only +libinput
		opengl tslib vulkan +widgets
	"
	[network]="brotli gssapi libproxy sctp"
	[sql]="mysql oci8 odbc postgres +sqlite"
	[widgets]="cups gtk"

	[optfeature]="wayland" #864509
)
IUSE="${QT6_IUSE[*]}"
REQUIRED_USE="
	$(
		printf '%s? ( gui ) ' ${QT6_IUSE[gui]//+/}
		printf '%s? ( network ) ' ${QT6_IUSE[network]//+/}
		printf '%s? ( sql ) ' ${QT6_IUSE[sql]//+/}
		printf '%s? ( gui widgets ) ' ${QT6_IUSE[widgets]//+/}
	)
	accessibility? ( X dbus )
	eglfs? ( opengl )
	gui? ( || ( X eglfs wayland ) )
	libinput? ( udev )
	sql? ( || ( ${QT6_IUSE[sql]//+/} ) )
	test? (
		gui icu
		sql? ( sqlite )
	)
"

# groups:
# - global (configure.cmake)
# - qtcore (src/corelib/configure.cmake)
# - qtgui (src/gui/configure.cmake)
# - qtnetwork (src/network/configure.cmake)
# - qtprintsupport (src/printsupport/configure.cmake) [gui+widgets]
# - qtsql (src/plugins/sqldrivers/configure.cmake)
RDEPEND="
	sys-libs/zlib:=
	ssl? ( dev-libs/openssl:= )
	udev? ( virtual/libudev:= )
	zstd? ( app-arch/zstd:= )

	app-crypt/libb2
	dev-libs/double-conversion:=
	dev-libs/glib:2
	dev-libs/libpcre2:=[pcre16,unicode(+)]
	icu? ( dev-libs/icu:= )
	systemd? ( sys-apps/systemd:= )

	dbus? ( sys-apps/dbus )
	gui? (
		media-libs/fontconfig
		media-libs/freetype:2
		media-libs/harfbuzz:=
		media-libs/libjpeg-turbo:=
		media-libs/libpng:=
		x11-libs/libdrm
		x11-libs/libxkbcommon[X?]
		X? (
			x11-libs/libICE
			x11-libs/libSM
			x11-libs/libX11
			x11-libs/libxcb:=
			x11-libs/xcb-util-cursor
			x11-libs/xcb-util-image
			x11-libs/xcb-util-keysyms
			x11-libs/xcb-util-renderutil
			x11-libs/xcb-util-wm
		)
		accessibility? ( app-accessibility/at-spi2-core:2 )
		eglfs? ( media-libs/mesa[gbm(+)] )
		evdev? ( sys-libs/mtdev )
		libinput? ( dev-libs/libinput:= )
		opengl? ( media-libs/libglvnd[X?] )
		tslib? ( x11-libs/tslib )
		widgets? (
			cups? ( net-print/cups )
			gtk? (
				x11-libs/gdk-pixbuf:2
				x11-libs/gtk+:3
				x11-libs/pango
			)
		)
	)
	network? (
		brotli? ( app-arch/brotli:= )
		gssapi? ( virtual/krb5 )
		libproxy? ( net-libs/libproxy )
	)
	sql? (
		mysql? ( dev-db/mysql-connector-c:= )
		oci8? ( dev-db/oracle-instantclient:=[sdk] )
		odbc? ( dev-db/unixODBC )
		postgres? ( dev-db/postgresql:* )
		sqlite? ( dev-db/sqlite:3 )
	)
"
DEPEND="
	${RDEPEND}
	X? ( x11-base/xorg-proto )
	gui? (
		vulkan? ( dev-util/vulkan-headers )
	)
	network? (
		sctp? ( net-misc/lksctp-tools )
	)
"
PDEPEND="wayland? ( =dev-qt/qtwayland-${PV}*:6 )"

src_prepare() {
	qt6-build_src_prepare

	if use test; then
		# test itself has -Werror=strict-aliasing issues, drop for simplicity
		sed -e '/add_subdirectory(qsharedpointer)/d' \
			-i tests/auto/corelib/tools/CMakeLists.txt || die
	fi
}

src_configure() {
	local mycmakeargs=(
		-DINSTALL_ARCHDATADIR="${QT6_ARCHDATADIR}"
		-DINSTALL_BINDIR="${QT6_BINDIR}"
		-DINSTALL_DATADIR="${QT6_DATADIR}"
		-DINSTALL_DOCDIR="${QT6_DOCDIR}"
		-DINSTALL_EXAMPLESDIR="${QT6_EXAMPLESDIR}"
		-DINSTALL_INCLUDEDIR="${QT6_HEADERDIR}"
		-DINSTALL_LIBDIR="${QT6_LIBDIR}"
		-DINSTALL_LIBEXECDIR="${QT6_LIBEXECDIR}"
		-DINSTALL_MKSPECSDIR="${QT6_MKSPECSDIR}"
		-DINSTALL_PLUGINSDIR="${QT6_PLUGINDIR}"
		-DINSTALL_QMLDIR="${QT6_QMLDIR}"
		-DINSTALL_SYSCONFDIR="${QT6_SYSCONFDIR}"
		-DINSTALL_TRANSLATIONSDIR="${QT6_TRANSLATIONDIR}"

		-DQT_FEATURE_precompile_header=OFF
		$(qt_feature ssl openssl)
		$(qt_feature ssl openssl_linked)
		$(qt_feature udev libudev)
		$(qt_feature zstd)

		# qtcore
		$(qt_feature icu)
		$(qt_feature systemd journald)

		# tools
		-DQT_FEATURE_androiddeployqt=OFF

		# modules
		$(qt_feature concurrent)
		$(qt_feature dbus)
		$(qt_feature gui)
		$(qt_feature gui testlib) # shared w/ gui
		$(qt_feature network)
		$(qt_feature sql)
		$(qt_feature xml)
	)

	use gui && mycmakeargs+=(
		$(qt_feature X xcb)
		$(qt_feature X system_xcb_xinput)
		$(qt_feature X xkbcommon_x11)
		$(cmake_use_find_package X X11) # needed for truly no automagic
		$(qt_feature accessibility accessibility_atspi_bridge)
		$(qt_feature eglfs)
		$(qt_feature evdev)
		$(qt_feature evdev mtdev)
		$(qt_feature gles2-only opengles2)
		$(qt_feature libinput)
		$(qt_feature opengl)
		$(qt_feature tslib)
		$(qt_feature vulkan)
		$(qt_feature widgets)
		-DQT_FEATURE_system_textmarkdownreader=OFF # TODO?: package md4c
	) && use widgets && mycmakeargs+=(
		$(qt_feature cups) # qtprintsupport is enabled w/ gui+widgets
		$(qt_feature gtk gtk3)
	)

	use network && mycmakeargs+=(
		$(qt_feature brotli)
		$(qt_feature gssapi)
		$(qt_feature libproxy)
		$(qt_feature sctp)
		$(usev test -DQT_SKIP_DOCKER_COMPOSE=ON)
	)

	use sql && mycmakeargs+=(
		-DQT_FEATURE_sql_db2=OFF # unpackaged
		-DQT_FEATURE_sql_ibase=OFF # unpackaged
		$(qt_feature mysql sql_mysql)
		$(qt_feature oci8 sql_oci)
		$(usev oci8 -DOracle_ROOT="${ESYSROOT}"/usr/$(get_libdir)/oracle/client)
		$(qt_feature odbc sql_odbc)
		$(qt_feature postgres sql_psql)
		$(qt_feature sqlite sql_sqlite)
		$(qt_feature sqlite system_sqlite)
		-DQT_FEATURE_sql_tds=OFF # currently a no-op in CMakeLists.txt
	)

	qt6-build_src_configure
}

src_test() {
	local -x TZ=UTC
	local -x LC_TIME=C

	local CMAKE_SKIP_TESTS=(
		# broken with out-of-source + if qtbase is not already installed
		tst_moc
		tst_qmake
		# needs x11/opengl, we *could* run these but tend to be flaky
		# when opengl rendering is involved (even if software-only)
		tst_qopengl{,config,widget,window}
		tst_qgraphicsview
		tst_qx11info
		# fails with network sandbox
		tst_qdnslookup
		# typical to lack SCTP support on non-generic kernels
		tst_qsctpsocket
		# these can be flaky depending on the environment/toolchain
		tst_qlogging # backtrace log test can easily vary
		tst_qrawfont # can be affected by available fonts
		tst_qstorageinfo # checks mounted filesystems
		# flaky due to using different test framework and fails with USE=-gui
		tst_selftests
		# known failing when using clang+glibc+stdc++, needs looking into
		tst_qthread
		# partially failing on x86 chroots and seemingly(?) harmless (dev-qt
		# revdeps tests pass), skip globally to avoid keywording flakiness
		tst_json
		tst_qcolorspace
		tst_qdoublevalidator
		tst_qglobal
		tst_qglyphrun
		tst_qvectornd
		tst_rcc
		# note: for linux, upstream only really runs+maintains tests for amd64
		# https://doc.qt.io/qt-6/supported-platforms.html
	)

	qt6-build_src_test
}

src_install() {
	qt6-build_src_install

	qt6_symlink_binary_to_path qmake 6 #863395

	if use test; then
		local delete_bins=( # need a better way to handle this
			clientserver copier crashingServer desktopsettingsaware_helper
			echo fileWriterProcess modal_helper nospace 'one space'
			paster qcommandlineparser_test_helper qfileopeneventexternal
			socketprocess syslocaleapp tst_qhashseed_helper 'two space s'
			write-read-write
		)
		local delete=( # sigh
			"${D}${QT6_BINDIR}"/test*
			"${delete_bins[@]/#/${D}${QT6_BINDIR}/}"
		)
		# using -f given not tracking which tests may be skipped or not
		rm -rf -- "${delete[@]}" || die
	fi
}
