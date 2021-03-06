# Copyright 1999-2019 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=6

SSL_CERT_MANDATORY=1

inherit eutils pam rebar ssl-cert systemd

DESCRIPTION="Robust, scalable and extensible XMPP server"
HOMEPAGE="https://www.ejabberd.im/ https://github.com/processone/ejabberd/"
SRC_URI="https://www.process-one.net/downloads/${PN}/${PV}/${P}.tgz
	-> ${P}.tar.gz"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64 ~arm ~ia64 ~ppc ~sparc ~x86"
REQUIRED_USE="mssql? ( odbc )"
# TODO: Add 'tools' flag.
IUSE="captcha debug full-xml hipe ldap mssql mysql odbc pam postgres redis
	roster-gw sip sqlite stun zlib"

RESTRICT="test"

# TODO: Add dependencies for 'tools' flag enabled.
# TODO: tools? (
# TODO:		>=dev-erlang/luerl-0.3
# TODO: )
DEPEND=">=dev-lang/erlang-19.1[hipe?,odbc?,ssl]
	>=dev-erlang/cache_tab-1.0.20
	>=dev-erlang/eimp-1.0.12
	>=dev-erlang/fast_tls-1.1.2
	>=dev-erlang/fast_xml-1.1.37
	>=dev-erlang/fast_yaml-1.0.20
	>=dev-erlang/yconf-1.0.0
	>=dev-erlang/jiffy-0.14.8
	>=dev-erlang/jose-1.8.4
	>=dev-erlang/lager-3.6.10
	>=dev-erlang/p1_oauth2-0.6.5
	>=dev-erlang/p1_utils-1.0.16
	>=dev-erlang/stringprep-1.0.17
	>=dev-erlang/xmpp-1.4.0
	>=dev-erlang/pkix-1.0.3
	>=dev-erlang/mqtree-1.0.4
	>=net-im/jabber-base-0.01
	ldap? ( =net-nds/openldap-2* )
	mysql? ( >=dev-erlang/p1_mysql-1.0.11 )
	odbc? ( dev-db/unixODBC )
	pam? ( >=dev-erlang/epam-1.0.6 )
	postgres? ( >=dev-erlang/p1_pgsql-1.1.8 )
	redis? ( >=dev-erlang/eredis-1.0.8 )
	sip? ( >=dev-erlang/esip-1.0.30 )
	sqlite? ( >=dev-erlang/sqlite3-1.1.6 )
	stun? ( >=dev-erlang/stun-1.0.29 )
	zlib? ( >=dev-erlang/ezlib-1.0.6 )"
RDEPEND="${DEPEND}
	captcha? ( media-gfx/imagemagick[truetype,png] )"

DOCS=( CHANGELOG.md README.md )
PATCHES=( "${FILESDIR}/${P}-ejabberdctl.patch"
	"${FILESDIR}/${P}-0002-Dont-overwrite-service-file.patch" )

EJABBERD_CERT="${EPREFIX}/etc/ssl/ejabberd/server.pem"
# Paths in net-im/jabber-base
JABBER_ETC="${EPREFIX}/etc/jabber"
JABBER_LOG="${EPREFIX}/var/log/jabber"
JABBER_SPOOL="${EPREFIX}/var/spool/jabber"

# Adjust example configuration file to Gentoo.
# - Use our sample certificate.
adjust_config() {
	sed -rne "/^certfiles:/{p;a\  - ${EJABBERD_CERT}" -e ":a;n;/^\s+-/ba};p" \
		-i "${S}/ejabberd.yml.example" \
		|| die 'failed to adjust example config'
}

# Set paths to ejabberd lib directory consistently to point always to directory
# suffixed with version.
correct_ejabberd_paths() {
	sed -e "/^EJABBERDDIR[[:space:]]*=/{s:ejabberd:${P}:}" \
		-i "${S}/Makefile.in" \
		|| die 'failed to set ejabberd path in Makefile.in'
	sed -e "/EJABBERD_BIN_PATH=/{s:ejabberd:${P}:}" \
		-i "${S}/ejabberdctl.template" \
		|| die 'failed to set ejabberd path in ejabberdctl.template'
}

# Get epam-wrapper from 'files' directory and correct path to lib directory in
# it. epam-wrapper is placed into work directory. It is assumed no epam-wrapper
# file exists there already.
customize_epam_wrapper() {
	local epam_wrapper_src="$1"
	local epam_wrapper_dst="${S}/epam-wrapper"

	[[ -e ${epam_wrapper_dst} ]] && die 'epam-wrapper already exists'
	sed -r -e "s@^(ERL_LIBS=).*\$@\1${EPREFIX}$(get_erl_libs)@" \
		"${epam_wrapper_src}" >"${epam_wrapper_dst}" \
		|| die 'failed to install epam-wrapper'
}

# Check if we are missing a default certificate.
ejabberd_cert_missing() {
	if grep -qs "^\s\+- ${EJABBERD_CERT}" "${EROOT%/}${JABBER_ETC}/ejabberd.yml"; then
		if [[ -f "${EROOT%/}${EJABBERD_CERT}" ]]; then
			# default certificate is present in config and exists - not installing
			return 1
		else
			# default certificate is present in config
			# but doesn't exist - need to install one
			return 0
		fi
	fi
	# no default certificate in config - not installing
	return 1
}

# Generate and install sample ejabberd certificate. It's installed into
# EJABBERD_CERT path.
ejabberd_cert_install() {
	SSL_ORGANIZATION="${SSL_ORGANIZATION:-ejabberd XMPP Server}"
	install_cert "${EJABBERD_CERT%.*}"
	chown root:jabber "${EROOT%/}${EJABBERD_CERT}" || die
	chmod 0440 "${EROOT%/}${EJABBERD_CERT}" || die
}

# Get path to ejabberd lib directory.
#
# This is the path ./configure script Base for this path is path set in
# ./configure script which is /usr/lib by default. If libdir is explicitely set
# to something else than this should be adjusted here as well.
get_ejabberd_path() {
	echo "/usr/$(get_libdir)/${P}"
}

# Make ejabberd.service for systemd from upstream provided template.
make_ejabberd_service() {
	sed -r \
		-e 's!@ctlscriptpath@!/usr/sbin!g' \
		-e 's!^(User|Group)=(.*)!\1=jabber!' \
		-e 's!^(After)=(.*)!\1=epmd.service network.target!' \
		-e '/^After=/ a Requires=epmd.service' \
		"${PN}.service.template" >"${PN}.service" \
		|| die 'failed to make ejabberd.service'
}

# Set paths to defined by net-im/jabber-base.
set_jabberbase_paths() {
	sed -e "/^ETCDIR[[:space:]]*=/{s:@sysconfdir@/ejabberd:${JABBER_ETC}:}" \
		-e "/^LOGDIR[[:space:]]*=/{s:@localstatedir@/log/ejabberd:${JABBER_LOG}:}" \
		-e "/^SPOOLDIR[[:space:]]*=/{s:@localstatedir@/lib/ejabberd:${JABBER_SPOOL}:}" \
		-i "${S}/Makefile.in" \
		|| die 'failed to set paths in Makefile.in'
	sed -e "s|\(ETC_DIR:=\"\){{sysconfdir}}[^\"]*|\1${JABBER_ETC}|" \
		-e "s|\(LOGS_DIR:=\"\){{localstatedir}}[^\"]*|\1${JABBER_LOG}|" \
		-e "s|\(SPOOL_DIR:=\"\){{localstatedir}}[^\"]*|\1${JABBER_SPOOL}|" \
		-i "${S}/ejabberdctl.template" \
		|| die 'failed to set paths ejabberdctl.template'
}

# Skip installing docs because it's only COPYING that's installed by Makefile.
skip_docs() {
	gawk -i inplace '
/# Documentation/, /^[[:space:]]*#?[[:space:]]*$/ {
	if ($0 ~ /^[[:space:]]*#?[[:space:]]*$/) {
		print $0;
	} else {
		next;
	}
}
1
' "${S}/Makefile.in" || die 'failed to remove docs section from Makefile.in'
}

src_prepare() {
	default

	rebar_remove_deps
	correct_ejabberd_paths
	set_jabberbase_paths
	make_ejabberd_service
	skip_docs
	adjust_config
	customize_epam_wrapper "${FILESDIR}/epam-wrapper"

	rebar_fix_include_path fast_xml
	rebar_fix_include_path p1_utils
	rebar_fix_include_path xmpp

	# Fix bug #591862. ERL_LIBS should point directly to ejabberd directory
	# rather than its parent which is default. That way ejabberd directory
	# takes precedence is module lookup.
	local ejabberd_erl_libs="$(get_ejabberd_path):$(get_erl_libs)"
	sed -e "s|\(ERL_LIBS=\){{libdir}}.*|\1${ejabberd_erl_libs}|" \
		-i "${S}/ejabberdctl.template" \
		|| die 'failed to set ERL_LIBS in ejabberdctl.template'

	sed -e "s|\(AC_INIT(ejabberd, \)m4_esyscmd([^)]*)|\1[$PV]|" \
		-i configure.ac || die "Failed to write correct version to configure"
	# eautoreconf # required in case of download from github
}

src_configure() {
	econf \
		--docdir="${EPREFIX}/usr/share/doc/${PF}/html" \
		--enable-user=jabber \
		--disable-system-deps \
		$(use_enable debug) \
		$(use_enable full-xml) \
		$(use_enable hipe) \
		$(use_enable mssql) \
		$(use_enable mysql) \
		$(use_enable odbc) \
		$(use_enable pam) \
		$(use_enable postgres pgsql) \
		$(use_enable redis) \
		$(use_enable roster-gw roster-gateway-workaround) \
		$(use_enable sqlite) \
		$(use_enable sip) \
		$(use_enable stun) \
		$(use_enable zlib)

	# more options to support
	# --enable-elixir requires https://github.com/elixir-lang/elixir
}

src_compile() {
	emake REBAR='rebar -v' src
}

src_install() {
	default

	keepdir /var/lib/lock/ejabberdctl
	rm -rf "${ED%/}/var/log" || die
	rm -rf "${ED%/}/var/spool" || die

	if use pam; then
		local epam_path="$(get_ejabberd_path)/priv/bin/epam"

		pamd_mimic_system xmpp auth account || die "cannot create pam.d file"
		into "$(get_ejabberd_path)/priv"
		newbin epam-wrapper epam
	fi

	newconfd "${FILESDIR}/${PN}.confd" "${PN}"
	newinitd "${FILESDIR}/${PN}.initd" "${PN}"
	systemd_dounit "${PN}.service"
	systemd_dotmpfilesd "${FILESDIR}/${PN}.tmpfiles.conf"

	insinto /etc/logrotate.d
	newins "${FILESDIR}/${PN}.logrotate" "${PN}"
}

pkg_preinst() {
	if use pam; then
		einfo "Adding jabber user to epam group to allow ejabberd to use PAM" \
			"authentication"
		# See
		# <https://docs.ejabberd.im/admin/configuration/#pam-authentication>.
		# epam binary is installed by dev-erlang/epam package, therefore SUID
		# is set by that package. Instead of jabber group it uses epam group,
		# therefore we need to add jabber user to epam group.
		usermod -a -G epam jabber || die
	fi
}

pkg_postinst() {
	if [[ ! ${REPLACING_VERSIONS} ]]; then
		echo
		elog "For configuration instructions, please see"
		elog "  http://www.process-one.net/en/ejabberd/docs/"
		echo
		if [[ " ${REPLACING_VERSIONS} " =~ \ 2\. ]]; then
			ewarn "If you have used pubsub in ejabberd-2.* you may encounter issues after"
			ewarn "migration to ${PV}. pubsub data may not be migrated automatically and"
			ewarn "you may need to run migration script manually, see:"
			ewarn
			ewarn "  https://github.com/processone/ejabberd/issues/479#issuecomment-124497456"
			ewarn
			ewarn "In case you don't care about all stored moods, activities, geoinfo and you"
			ewarn "know you don't store in pubsub anything important, you can just remove"
			ewarn "pubsub tables:"
			ewarn
			ewarn "  rm ${EROOT%/}${JABBER_SPOOL}/pubsub_*"
			ewarn
			ewarn "See also: https://bugs.gentoo.org/show_bug.cgi?id=588244"
			echo
		fi
	elif [[ -f ${EROOT}etc/jabber/ejabberd.cfg ]]; then
		elog "Ejabberd now defaults to using a YAML format for its config file."
		elog "The old ejabberd.cfg file can be converted using the following instructions:"
		echo
		elog "1. Make sure all processes related to the previous version of ejabberd aren't"
		elog "   running. Usually this just means the ejabberd and epmd daemons and possibly"
		elog "   the pam-related process (epam) if pam support is enabled."
		elog "2. Run \`ejabberdctl start\` with sufficient permissions. Note that this can"
		elog "   fail to start ejabberd properly for various reasons. Check ejabberd's main"
		elog "   log file at /var/log/jabber/ejabberd.log to confirm it started successfully."
		elog "3. Run"
		elog "     \`ejabberdctl convert_to_yaml /etc/jabber/ejabberd.cfg /etc/jabber/ejabberd.yml.new\`"
		elog "   with sufficient permissions, edit and rename /etc/jabber/ejabberd.yml.new to"
		elog "   /etc/jabber/ejabberd.yml, and finally restart ejabberd with the new config"
		elog "   file."
		echo
	fi

	if ejabberd_cert_missing; then
		ejabberd_cert_install
	fi
}
